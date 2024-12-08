// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "src/base/RecipeMarketHubBase.sol";
import "src/WrappedVault.sol";

import { console } from "lib/forge-std/src/console.sol";
import { MockERC20, ERC20 } from "../../mocks/MockERC20.sol";
import { MockERC4626 } from "test/mocks/MockERC4626.sol";
import { RecipeMarketHubTestBase } from "../../utils/RecipeMarketHub/RecipeMarketHubTestBase.sol";
import { FixedPointMathLib } from "lib/solmate/src/utils/FixedPointMathLib.sol";

contract TestFuzz_Fill_IPGdaOffer_RecipeMarketHub is RecipeMarketHubTestBase {
    using FixedPointMathLib for uint256;

    address IP_ADDRESS;
    address FRONTEND_FEE_RECIPIENT;

    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimiumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeMarketHubTests(protocolFee, minimiumFrontendFee);

        IP_ADDRESS = ALICE_ADDRESS;
        FRONTEND_FEE_RECIPIENT = CHARLIE_ADDRESS;
    }

    function testFuzz_DirectFill_Upfront_IPGdaOffer_ForTokens(uint256 offerAmount, uint256 fillAmount) external {
        offerAmount = bound(offerAmount, 1e6, 1e30);
        fillAmount = bound(fillAmount, 1e6, offerAmount);

        uint256 frontendFee = recipeMarketHub.minimumFrontendFee();
        bytes32 marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        // Create a fillable IPGda offer
        bytes32 offerHash = createIPGdaOffer_WithTokens(marketHash, offerAmount, IP_ADDRESS);

        // Mint liquidity tokens to the AP to fill the offer
        mockLiquidityToken.mint(BOB_ADDRESS, fillAmount);
        vm.startPrank(BOB_ADDRESS);
        mockLiquidityToken.approve(address(recipeMarketHub), fillAmount);
        vm.stopPrank();

        (, uint256 expectedProtocolFeeAmount, uint256 expectedFrontendFeeAmount, uint256 expectedIncentiveAmount) =
            calculateIPGdaOfferExpectedIncentiveAndFrontendFee(offerHash, offerAmount, fillAmount, address(mockIncentiveToken));

        // Expect events for transfers
        vm.expectEmit(true, true, false, true, address(mockIncentiveToken));
        emit ERC20.Transfer(address(recipeMarketHub), BOB_ADDRESS, expectedIncentiveAmount);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(BOB_ADDRESS, address(0), fillAmount);

        vm.expectEmit(false, false, false, false, address(recipeMarketHub));
        emit RecipeMarketHubBase.IPGdaOfferFilled(0, address(0), 0, address(0), new uint256[](0), new uint256[](0), new uint256[](0));

        // Record logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();
        // Fill the offer
        vm.startPrank(BOB_ADDRESS);
        recipeMarketHub.fillIPGdaOffers(offerHash, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        (,,,, uint256 resultingQuantity, uint256 resultingRemainingQuantity,) = recipeMarketHub.offerHashToIPGdaOffer(offerHash);
        assertEq(resultingRemainingQuantity, resultingQuantity - fillAmount);

        // Extract the Weiroll wallet address
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[1].topics[2])));
        assertGt(weirollWallet.code.length, 0); // Ensure weirollWallet is valid

        // Ensure AP received the correct incentive amount
        assertEq(mockIncentiveToken.balanceOf(BOB_ADDRESS), expectedIncentiveAmount);

        // Ensure weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);

        // Check frontend fee recipient received correct fee
        assertEq(recipeMarketHub.feeClaimantToTokenToAmount(FRONTEND_FEE_RECIPIENT, address(mockIncentiveToken)), expectedFrontendFeeAmount);

        // Check the protocol fee recipient received the correct fee
        assertEq(recipeMarketHub.feeClaimantToTokenToAmount(OWNER_ADDRESS, address(mockIncentiveToken)), expectedProtocolFeeAmount);
    }

    function testFuzz_DirectFill_Upfront_IPGdaOffer_ForPoints(uint256 offerAmount, uint256 fillAmount) external {
        offerAmount = bound(offerAmount, 1e6, 1e30);
        fillAmount = bound(fillAmount, 1e6, offerAmount);

        uint256 frontendFee = recipeMarketHub.minimumFrontendFee();
        bytes32 marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        // Mint liquidity tokens to the AP to fill the offer
        mockLiquidityToken.mint(BOB_ADDRESS, fillAmount);
        vm.startPrank(BOB_ADDRESS);
        mockLiquidityToken.approve(address(recipeMarketHub), fillAmount);
        vm.stopPrank();

        // Create a fillable IP offer
        (bytes32 offerHash, Points points) = createIPGdaOffer_WithPoints(marketHash, offerAmount, IP_ADDRESS);

        (, uint256 expectedProtocolFeeAmount, uint256 expectedFrontendFeeAmount, uint256 expectedIncentiveAmount) =
            calculateIPGdaOfferExpectedIncentiveAndFrontendFee(offerHash, offerAmount, fillAmount, address(points));

        // Expect events for transfers
        vm.expectEmit(true, true, false, true, address(points));
        emit Points.Award(OWNER_ADDRESS, expectedProtocolFeeAmount, IP_ADDRESS);

        vm.expectEmit(true, true, false, true, address(points));
        emit Points.Award(FRONTEND_FEE_RECIPIENT, expectedFrontendFeeAmount, IP_ADDRESS);

        // Expect events for transfers
        vm.expectEmit(true, true, false, true, address(points));
        emit Points.Award(BOB_ADDRESS, expectedIncentiveAmount, IP_ADDRESS);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(BOB_ADDRESS, address(0), fillAmount);

        vm.expectEmit(false, false, false, false, address(recipeMarketHub));
        emit RecipeMarketHubBase.IPGdaOfferFilled(0, address(0), 0, address(0), new uint256[](0), new uint256[](0), new uint256[](0));

        // Record logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();
        // Fill the offer
        vm.startPrank(BOB_ADDRESS);
        recipeMarketHub.fillIPGdaOffers(offerHash, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        (,,,, uint256 resultingQuantity, uint256 resultingRemainingQuantity,) = recipeMarketHub.offerHashToIPGdaOffer(offerHash);
        assertEq(resultingRemainingQuantity, resultingQuantity - fillAmount);

        // Extract the Weiroll wallet address
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[3].topics[2])));
        assertGt(weirollWallet.code.length, 0); // Ensure weirollWallet is valid

        // Ensure weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);
    }

    function testFuzz_RevertIf_OfferExpired(uint256 offerAmount, uint256 fillAmount, uint256 timeDelta) external {
        offerAmount = bound(offerAmount, 1e6, 1e30);
        fillAmount = bound(fillAmount, 1e6, offerAmount);
        timeDelta = bound(timeDelta, 30 days + 1, 365 days);

        uint256 frontendFee = recipeMarketHub.minimumFrontendFee();
        bytes32 marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        // Create an offer with the specified amount
        bytes32 offerHash = createIPGdaOffer_WithTokens(marketHash, offerAmount, IP_ADDRESS);

        // Warp to time beyond the expiry
        vm.warp(block.timestamp + timeDelta);

        // Expect revert due to offer expiration
        vm.expectRevert(RecipeMarketHubBase.OfferExpired.selector);
        recipeMarketHub.fillIPGdaOffers(offerHash, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
    }

    function testFuzz_RevertIf_NotEnoughRemainingQuantity(uint256 offerAmount, uint256 fillAmount) external {
        offerAmount = bound(offerAmount, 1e18, 1e30);
        fillAmount = offerAmount + bound(fillAmount, 1, 100e18); // Fill amount exceeds offerAmount

        uint256 frontendFee = recipeMarketHub.minimumFrontendFee();
        bytes32 marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        // Create a fillable IP offer
        bytes32 offerHash = createIPGdaOffer_WithTokens(marketHash, offerAmount, IP_ADDRESS);

        // Expect revert due to insufficient remaining quantity
        vm.expectRevert(RecipeMarketHubBase.NotEnoughRemainingQuantity.selector);
        recipeMarketHub.fillIPGdaOffers(offerHash, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
    }

    function testFuzz_RevertIf_MismatchedBaseAsset(uint256 offerAmount, uint256 fillAmount) external {
        offerAmount = bound(offerAmount, 1e6, 1e30);
        fillAmount = bound(fillAmount, 1e6, offerAmount);

        uint256 frontendFee = recipeMarketHub.minimumFrontendFee();
        bytes32 marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        // Create a fillable IP offer
        bytes32 offerHash = createIPGdaOffer_WithTokens(marketHash, offerAmount, IP_ADDRESS);

        // Use a different vault with a mismatched base asset
        address incorrectVault = address(new MockERC4626(mockIncentiveToken)); // Mismatched asset

        // Expect revert due to mismatched base asset
        vm.expectRevert(RecipeMarketHubBase.MismatchedBaseAsset.selector);
        recipeMarketHub.fillIPGdaOffers(offerHash, fillAmount, incorrectVault, FRONTEND_FEE_RECIPIENT);
    }

    function testFuzz_RevertIf_ZeroQuantityFill(uint256 offerAmount) external {
        offerAmount = bound(offerAmount, 1e6, 1e30);

        uint256 frontendFee = recipeMarketHub.minimumFrontendFee();
        bytes32 marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        // Create a fillable IP offer
        bytes32 offerHash = createIPGdaOffer_WithTokens(marketHash, offerAmount, IP_ADDRESS);

        // Expect revert due to zero quantity fill
        vm.expectRevert(RecipeMarketHubBase.CannotPlaceZeroQuantityOffer.selector);
        recipeMarketHub.fillIPGdaOffers(offerHash, 0, address(0), FRONTEND_FEE_RECIPIENT);
    }

    function testFuzz_GdaMath_IPGdaOffer_ForTokens(uint256 offerAmount, uint256 fillAmount, uint256 timeSinceAuctionStart) external {
        offerAmount = bound(offerAmount, 1e6, 1e30);
        fillAmount = bound(fillAmount, 1e6, offerAmount);
        timeSinceAuctionStart = bound(timeSinceAuctionStart, 1, 30 days);

        uint256 timestamp = vm.getBlockTimestamp();

        uint256 frontendFee = recipeMarketHub.minimumFrontendFee();
        bytes32 marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        // Create a fillable IPGda offer
        bytes32 offerHash = createIPGdaOffer_WithTokens(marketHash, offerAmount, IP_ADDRESS);

        // Mint liquidity tokens to the AP to fill the offer
        mockLiquidityToken.mint(BOB_ADDRESS, fillAmount);
        vm.startPrank(BOB_ADDRESS);
        mockLiquidityToken.approve(address(recipeMarketHub), fillAmount);
        vm.stopPrank();

        (, uint256 expectedProtocolFeeAmount, uint256 expectedFrontendFeeAmount, uint256 expectedIncentiveAmount) =
            calculateIPGdaOfferExpectedIncentiveAndFrontendFee(offerHash, offerAmount, fillAmount, address(mockIncentiveToken));

        // uint256 expectedIncentiveAmountInLinearFill =
        uint256 fillPercentage = FixedPointMathLib.divWadDown(fillAmount, offerAmount);
        uint256 totalIncentivesOffered = recipeMarketHub.getMaxIncentiveAmountsOfferedForIPGdaOffer(offerHash, address(mockIncentiveToken));
        uint256 totalInitialIncentivesOffered = recipeMarketHub.getMinIncentiveAmountsOfferedForIPGdaOffer(offerHash, address(mockIncentiveToken));

        uint256 expectedIncentiveAmountInCaseOfLinearFill = FixedPointMathLib.mulWadDown(totalIncentivesOffered, fillPercentage);
        uint256 expectedIncentiveAmountInCaseOfInitialIncentiveRate = FixedPointMathLib.mulWadDown(totalInitialIncentivesOffered, fillPercentage);

        // Expect events for transfers
        vm.expectEmit(true, true, false, true, address(mockIncentiveToken));
        emit ERC20.Transfer(address(recipeMarketHub), BOB_ADDRESS, expectedIncentiveAmount);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(BOB_ADDRESS, address(0), fillAmount);

        vm.expectEmit(false, false, false, false, address(recipeMarketHub));
        emit RecipeMarketHubBase.IPGdaOfferFilled(0, address(0), 0, address(0), new uint256[](0), new uint256[](0), new uint256[](0));

        // Record logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();
        // Fill the offer
        vm.startPrank(BOB_ADDRESS);
        vm.warp(timestamp + timeSinceAuctionStart);
        recipeMarketHub.fillIPGdaOffers(offerHash, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        (,,,, uint256 resultingQuantity, uint256 resultingRemainingQuantity,) = recipeMarketHub.offerHashToIPGdaOffer(offerHash);
        assertEq(resultingRemainingQuantity, resultingQuantity - fillAmount);

        // Extract the Weiroll wallet address
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[1].topics[2])));
        assertGt(weirollWallet.code.length, 0); // Ensure weirollWallet is valid

        // Ensure AP received the correct incentive amount
        assertEq(mockIncentiveToken.balanceOf(BOB_ADDRESS), expectedIncentiveAmount);

        // Ensure AP received incentive amount which is always less than max budget
        assertEq(expectedIncentiveAmount <= expectedIncentiveAmountInCaseOfLinearFill, true);
        assertEq(expectedIncentiveAmount >= expectedIncentiveAmountInCaseOfInitialIncentiveRate, true);

        // Ensure weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);

        // Check frontend fee recipient received correct fee
        assertEq(recipeMarketHub.feeClaimantToTokenToAmount(FRONTEND_FEE_RECIPIENT, address(mockIncentiveToken)), expectedFrontendFeeAmount);

        // Check the protocol fee recipient received the correct fee
        assertEq(recipeMarketHub.feeClaimantToTokenToAmount(OWNER_ADDRESS, address(mockIncentiveToken)), expectedProtocolFeeAmount);
    }

    function testFuzz_Ffi_IPGdaOffer_ForTokens(uint256 offerAmount, uint256 fillAmount, uint256 timeSinceAuctionStart) external {
        offerAmount = 1e30;
        fillAmount = offerAmount / 2;
        // bound(fillAmount, 1e6, offerAmount);
        timeSinceAuctionStart = bound(timeSinceAuctionStart, 1, 30 days);

        uint256 timestamp = vm.getBlockTimestamp();

        uint256 frontendFee = recipeMarketHub.minimumFrontendFee();
        bytes32 marketHash = recipeMarketHub.createMarket(address(mockLiquidityToken), 30 days, frontendFee, NULL_RECIPE, NULL_RECIPE, RewardStyle.Upfront);

        // Create a fillable IPGda offer
        bytes32 offerHash = createIPGdaOffer_WithTokens(marketHash, offerAmount, IP_ADDRESS);

        // Mint liquidity tokens to the AP to fill the offer
        mockLiquidityToken.mint(BOB_ADDRESS, fillAmount);
        vm.startPrank(BOB_ADDRESS);
        mockLiquidityToken.approve(address(recipeMarketHub), fillAmount);
        vm.stopPrank();

        vm.warp(timestamp + timeSinceAuctionStart);
        uint256 timestamp_1 = vm.getBlockTimestamp();

        uint256 lastAuctionStartTime = recipeMarketHub.getLastAuctionStartTime(offerHash);
        uint256 differenceInTime = timestamp_1 - lastAuctionStartTime;

        uint256 denom = recipeMarketHub.getDenom(offerHash);

        (, uint256 expectedProtocolFeeAmount, uint256 expectedFrontendFeeAmount, uint256 expectedIncentiveAmount) =
            calculateIPGdaOfferExpectedIncentiveAndFrontendFee(offerHash, offerAmount, fillAmount, address(mockIncentiveToken));

        // uint256 expectedIncentiveAmountInLinearFill =
        uint256 fillPercentage = FixedPointMathLib.divWadDown(fillAmount, offerAmount);
        uint256 totalIncentivesOffered = recipeMarketHub.getMaxIncentiveAmountsOfferedForIPGdaOffer(offerHash, address(mockIncentiveToken));
        uint256 totalInitialIncentivesOffered = recipeMarketHub.getMinIncentiveAmountsOfferedForIPGdaOffer(offerHash, address(mockIncentiveToken));

        uint256 expectedIncentiveAmountInCaseOfLinearFill = FixedPointMathLib.mulWadDown(totalIncentivesOffered, fillPercentage);
        uint256 expectedIncentiveAmountInCaseOfInitialIncentiveRate = FixedPointMathLib.mulWadDown(totalInitialIncentivesOffered, fillPercentage);

        // Expect events for transfers
        vm.expectEmit(true, true, false, true, address(mockIncentiveToken));
        emit ERC20.Transfer(address(recipeMarketHub), BOB_ADDRESS, expectedIncentiveAmount);

        vm.expectEmit(true, false, false, true, address(mockLiquidityToken));
        emit ERC20.Transfer(BOB_ADDRESS, address(0), fillAmount);

        vm.expectEmit(false, false, false, false, address(recipeMarketHub));
        emit RecipeMarketHubBase.IPGdaOfferFilled(0, address(0), 0, address(0), new uint256[](0), new uint256[](0), new uint256[](0));

        // Record logs to capture Transfer events to get Weiroll wallet address
        vm.recordLogs();
        // Fill the offer
        vm.startPrank(BOB_ADDRESS);
        recipeMarketHub.fillIPGdaOffers(offerHash, fillAmount, address(0), FRONTEND_FEE_RECIPIENT);
        vm.stopPrank();

        string memory csvFilePath = "./results.csv";
        string[] memory inputs = new string[](8);
        inputs[0] = "python3";
        inputs[1] = "./append_to_csv.py";
        inputs[2] = csvFilePath;
        inputs[3] = vm.toString(fillAmount);
        inputs[4] = vm.toString(timestamp_1);
        inputs[5] = vm.toString(differenceInTime);
        inputs[6] = vm.toString(denom);
        inputs[7] = vm.toString(expectedIncentiveAmount);

        vm.ffi(inputs);

        (,,,, uint256 resultingQuantity, uint256 resultingRemainingQuantity,) = recipeMarketHub.offerHashToIPGdaOffer(offerHash);
        assertEq(resultingRemainingQuantity, resultingQuantity - fillAmount);

        // Extract the Weiroll wallet address
        address weirollWallet = address(uint160(uint256(vm.getRecordedLogs()[1].topics[2])));
        assertGt(weirollWallet.code.length, 0); // Ensure weirollWallet is valid

        // Ensure AP received the correct incentive amount
        assertEq(mockIncentiveToken.balanceOf(BOB_ADDRESS), expectedIncentiveAmount);

        // Ensure AP received incentive amount which is always less than max budget
        assertEq(expectedIncentiveAmount <= expectedIncentiveAmountInCaseOfLinearFill, true);
        assertEq(expectedIncentiveAmount >= expectedIncentiveAmountInCaseOfInitialIncentiveRate, true);

        // Ensure weiroll wallet got the liquidity
        assertEq(mockLiquidityToken.balanceOf(weirollWallet), fillAmount);

        // Check frontend fee recipient received correct fee
        assertEq(recipeMarketHub.feeClaimantToTokenToAmount(FRONTEND_FEE_RECIPIENT, address(mockIncentiveToken)), expectedFrontendFeeAmount);

        // Check the protocol fee recipient received the correct fee
        assertEq(recipeMarketHub.feeClaimantToTokenToAmount(OWNER_ADDRESS, address(mockIncentiveToken)), expectedProtocolFeeAmount);
    }

    /// @dev equivalent to `(x * y) / d` rounded down.
    function _mulDiv(int256 x, int256 y, int256 d) internal pure returns (int256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            z := mul(x, y)
            // equivalent to `require((x == 0 || z / x == y) && !(x == -1 && y == type(uint256).min))`
            if iszero(gt(or(iszero(x), eq(sdiv(z, x), y)), lt(not(x), eq(y, shl(255, 1))))) {
                mstore(0x00, 0xf96c5208) // `GDA__MulDivFailed()`
                revert(0x1c, 0x04)
            }
            z := sdiv(z, d)
        }
    }
}
