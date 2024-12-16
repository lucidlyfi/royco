// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { RecipeMarketHub, ERC20, RecipeMarketHubTestBase } from "../utils/RecipeMarketHub/RecipeMarketHubTestBase.sol";
import { console2 } from "../../lib/forge-std/src/console2.sol";
import { Vm } from "../../lib/forge-std/src/Vm.sol";

contract RecipeVerifier is RecipeMarketHubTestBase {
    string constant MAINNET_RPC_URL = "https://mainnet.gateway.tenderly.co";
    string constant ARBITRUM_RPC_URL = "https://arbitrum.gateway.tenderly.co";
    string constant BASE_RPC_URL = "https://base.gateway.tenderly.co";
    string constant ETH_SEPOLIA_RPC_URL = "https://sepolia.gateway.tenderly.co";

    bytes32 constant TRANSFER_EVENT_SIG = keccak256("Transfer(address,address,uint256)");

    RecipeMarketHub RECIPE_MARKET_HUB;
    bytes32 MARKET_HASH;
    uint256 fork;

    function setUp() public {
        // Replace this with the correct network if needed
        fork = vm.createFork(MAINNET_RPC_URL);

        // Replace with the correct RecipeMarketHub instance
        RECIPE_MARKET_HUB = RecipeMarketHub(0x783251f103555068c1E9D755f69458f39eD937c0);

        // Replace with the market hash of the market you want to verify
        MARKET_HASH = 0x83c459782b2ff36629401b1a592354fc085f29ae00cf97b803f73cac464d389b;
    }

    function getRoleOrAddress(address candidate, address ap, address wallet, address hub) internal pure returns (string memory) {
        if (candidate == ap) return "AP";
        if (candidate == wallet) return "WeirollWallet";
        if (candidate == hub) return "RecipeMarketHub";
        // Return the hex string of the address if not one of the known roles
        return _addressToString(candidate);
    }

    function test_RecipeMarketVerification() external {
        vm.selectFork(fork);

        console2.log("Verifying Market...");

        // Get the token to deposit for this market
        (, ERC20 marketInputToken, uint256 lockupTime,,,,) = RECIPE_MARKET_HUB.marketHashToWeirollMarket(MARKET_HASH);

        // Tune this amount for total offer amount
        uint256 offerAmount = 10_000 * (10 ** (marketInputToken.decimals()));
        // Tune this to simulate this amount of APs filling the offer
        uint256 numDepositors = 1;

        // Create an IP offer in the market
        address[] memory incentives = new address[](0);
        uint256[] memory incentiveAmounts = new uint256[](0);
        bytes32 ipOfferHash = RECIPE_MARKET_HUB.createIPOffer(MARKET_HASH, offerAmount, 0, incentives, incentiveAmounts);

        // Fill the IP Offer (Deposit phase)
        address[] memory aps = new address[](numDepositors);
        uint256[] memory fillAmounts = new uint256[](numDepositors);
        address[] memory weirollWallets = new address[](numDepositors);

        bytes32[] memory ipOfferHashes = new bytes32[](1);
        ipOfferHashes[0] = ipOfferHash;
        uint256[] memory depositorFillAmounts = new uint256[](1);

        console2.log("-----------------------------------------------------");
        console2.log("Deposit Recipe Flow:");
        console2.log("-----------------------------------------------------");

        // -------------------------
        // Deposit Phase (Filling the Offer)
        // -------------------------
        for (uint256 i = 0; i < numDepositors; i++) {
            (address ap,) = makeAddrAndKey(string(abi.encode(i)));
            aps[i] = ap;

            uint256 fillAmount = offerAmount / numDepositors;
            if (i == (numDepositors - 1)) {
                fillAmount = offerAmount - (fillAmount * (numDepositors - 1));
            }
            fillAmounts[i] = fillAmount;

            // Fund the AP and handle approval
            deal(address(marketInputToken), ap, fillAmount);
            vm.startPrank(ap);
            marketInputToken.approve(address(RECIPE_MARKET_HUB), fillAmount);

            depositorFillAmounts[0] = fillAmount;
            // Record the logs to capture Transfer events during deposit
            vm.recordLogs();
            // AP Fills the offer (no funding vault)
            RECIPE_MARKET_HUB.fillIPOffers(ipOfferHashes, depositorFillAmounts, address(0), address(0xbeef));
            vm.stopPrank();

            Vm.Log[] memory depositLogs = vm.getRecordedLogs();

            // Extract the Weiroll wallet address
            weirollWallets[i] = address(uint160(uint256(depositLogs[0].topics[2])));

            // Process each Transfer event log for deposit
            for (uint256 j = 0; j < depositLogs.length; j++) {
                Vm.Log memory log = depositLogs[j];

                if (log.topics[0] == TRANSFER_EVENT_SIG) {
                    address from = address(uint160(uint256(log.topics[1])));
                    address to = address(uint160(uint256(log.topics[2])));
                    uint256 amount = abi.decode(log.data, (uint256));

                    if (i == 0) {
                        string memory tokenName;
                        try ERC20(log.emitter).name() returns (string memory name) {
                            tokenName = name;
                        } catch {
                            tokenName = "<Unknown Token>";
                        }

                        // Identify roles or addresses
                        string memory fromEntity = getRoleOrAddress(from, aps[i], weirollWallets[i], address(RECIPE_MARKET_HUB));
                        string memory toEntity = getRoleOrAddress(to, aps[i], weirollWallets[i], address(RECIPE_MARKET_HUB));

                        // Single sentence log for deposit
                        console2.log(
                            string(abi.encodePacked(fromEntity, " sent ", _uintToString(amount), " ", tokenName, " to ", toEntity, " during deposit."))
                        );
                    }
                }
            }
        }

        // -------------------------
        // Withdrawal Phase
        // -------------------------

        // Time travel to when the deposits are withdrawable
        vm.warp(block.timestamp + lockupTime);

        console2.log("");
        console2.log("-----------------------------------------------------");
        console2.log("Withdrawal Recipe Flow:");
        console2.log("-----------------------------------------------------");

        for (uint256 i = 0; i < numDepositors; ++i) {
            vm.warp(block.timestamp + (i * 30 minutes));

            // Start recording logs before withdrawal
            vm.recordLogs();

            vm.startPrank(aps[i]);
            RECIPE_MARKET_HUB.executeWithdrawalScript(weirollWallets[i]);
            vm.stopPrank();

            Vm.Log[] memory withdrawLogs = vm.getRecordedLogs();

            bool apReceivedTokens = false;
            bool walletReceivedTokens = false;

            // Process each Transfer event log for withdrawal
            for (uint256 j = 0; j < withdrawLogs.length; j++) {
                Vm.Log memory log = withdrawLogs[j];

                if (log.topics[0] == TRANSFER_EVENT_SIG) {
                    address from = address(uint160(uint256(log.topics[1])));
                    address to = address(uint160(uint256(log.topics[2])));
                    uint256 amount = abi.decode(log.data, (uint256));

                    if (i == 0) {
                        string memory tokenName;
                        try ERC20(log.emitter).name() returns (string memory name) {
                            tokenName = name;
                        } catch {
                            tokenName = "<Unknown Token>";
                        }

                        // Identify roles or addresses
                        string memory fromEntity = getRoleOrAddress(from, aps[i], weirollWallets[i], address(RECIPE_MARKET_HUB));
                        string memory toEntity = getRoleOrAddress(to, aps[i], weirollWallets[i], address(RECIPE_MARKET_HUB));

                        // Single sentence log for withdrawal
                        console2.log(
                            string(abi.encodePacked(fromEntity, " sent ", _uintToString(amount), " ", tokenName, " to ", toEntity, " during withdrawal."))
                        );
                    }

                    if (to == aps[i]) {
                        apReceivedTokens = true;
                    } else if (to == weirollWallets[i]) {
                        walletReceivedTokens = true;
                    }
                }
            }

            // Ensure tokens ended up in either the AP or the Weiroll wallet
            assert(apReceivedTokens || walletReceivedTokens);
        }
        console2.log("-----------------------------------------------------");
        console2.log("Market Successfully Verified.");
    }

    // Utility function to convert uint to string
    function _uintToString(uint256 v) internal pure returns (string memory) {
        if (v == 0) {
            return "0";
        }
        uint256 j = v;
        uint256 length;
        while (j != 0) {
            length++;
            j /= 10;
        }
        bytes memory bstr = new bytes(length);
        uint256 k = length;
        j = v;
        while (j != 0) {
            k = k - 1;
            uint8 temp = uint8(48 + (j % 10));
            bstr[k] = bytes1(temp);
            j /= 10;
        }
        return string(bstr);
    }

    function _addressToString(address x) internal pure returns (string memory) {
        bytes memory s = new bytes(42);
        s[0] = "0";
        s[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            bytes1 b = bytes1(uint8(uint256(uint160(x)) / (2 ** (8 * (19 - i)))));
            bytes1 hi = bytes1(uint8(b) / 16);
            bytes1 lo = bytes1(uint8(b) - 16 * uint8(hi));
            s[2 + 2 * i] = _char(hi);
            s[3 + 2 * i] = _char(lo);
        }
        return string(s);
    }

    function _char(bytes1 b) internal pure returns (bytes1 c) {
        if (uint8(b) < 10) return bytes1(uint8(b) + 0x30);
        else return bytes1(uint8(b) + 0x57);
    }
}
