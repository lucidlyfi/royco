// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "src/base/RecipeMarketHubBase.sol";
import "src/WrappedVault.sol";

import { MockERC20 } from "../../mocks/MockERC20.sol";
import { RecipeMarketHubTestBase } from "../../utils/RecipeMarketHub/RecipeMarketHubTestBase.sol";
import { FixedPointMathLib } from "lib/solmate/src/utils/FixedPointMathLib.sol";

contract Test_IPOfferCreation_RecipeMarketHub is RecipeMarketHubTestBase {
    using FixedPointMathLib for uint256;

    function setUp() external {
        uint256 protocolFee = 0.01e18; // 1% protocol fee
        uint256 minimumFrontendFee = 0.001e18; // 0.1% minimum frontend fee
        setUpRecipeMarketHubTests(protocolFee, minimumFrontendFee);
    }

    function test_CreateIPOffer_ForTokens() external prankModifier(ALICE_ADDRESS) {
        bytes32 marketHash = createMarket();

        // Handle minting incentive token to the IP's address
        address[] memory tokensOffered = new address[](1);
        tokensOffered[0] = address(mockIncentiveToken);
        uint256[] memory incentiveAmountsOffered = new uint256[](1);
        incentiveAmountsOffered[0] = 1000e18;
        mockIncentiveToken.mint(ALICE_ADDRESS, 1000e18);
        mockIncentiveToken.approve(address(recipeMarketHub), 1000e18);

        uint256 quantity = 100_000e18; // The amount of input tokens to be deposited
        uint256 expiry = block.timestamp + 1 days; // Offer expires in 1 day

        // Calculate expected fees
        (,,, uint256 frontendFee,,,) = recipeMarketHub.marketHashToWeirollMarket(marketHash);
        uint256 incentiveAmount = incentiveAmountsOffered[0].divWadDown(1e18 + recipeMarketHub.protocolFee() + frontendFee);
        uint256 protocolFeeAmount = incentiveAmount.mulWadDown(recipeMarketHub.protocolFee());
        uint256 frontendFeeAmount = incentiveAmount.mulWadDown(frontendFee);

        // Expect the IPOfferCreated event to be emitted
        vm.expectEmit(false, false, false, false, address(recipeMarketHub));
        emit RecipeMarketHubBase.IPOfferCreated(
            0, // Expected offer ID (starts at 0)
            bytes32(0),
            marketHash, // Market ID
            quantity, // Total quantity
            tokensOffered, // Tokens offered
            incentiveAmountsOffered, // Amounts offered
            new uint256[](0),
            new uint256[](0),
            expiry // Expiry time
        );

        // MockERC20 should track calls to `transferFrom`
        vm.expectCall(
            address(mockIncentiveToken),
            abi.encodeWithSelector(
                ERC20.transferFrom.selector, ALICE_ADDRESS, address(recipeMarketHub), protocolFeeAmount + frontendFeeAmount + incentiveAmount
            )
        );

        // Create the IP offer
        bytes32 offerHash = recipeMarketHub.createIPOffer(
            marketHash, // Referencing the created market
            quantity, // Total input token amount
            expiry, // Expiry time
            tokensOffered, // Incentive tokens offered
            incentiveAmountsOffered // Incentive amounts offered
        );

        // Assertions on the offer
        assertEq(recipeMarketHub.numIPOffers(), 1); // IP offer count should be 1
        assertEq(recipeMarketHub.numAPOffers(), 0); // AP offers should remain 0

        // Use the helper function to retrieve values from storage
        uint256 frontendFeeStored = recipeMarketHub.getIncentiveToFrontendFeeAmountForIPOffer(offerHash, tokensOffered[0]);
        uint256 protocolFeeAmountStored = recipeMarketHub.getIncentiveToProtocolFeeAmountForIPOffer(offerHash, tokensOffered[0]);
        uint256 incentiveAmountStored = recipeMarketHub.getIncentiveAmountsOfferedForIPOffer(offerHash, tokensOffered[0]);

        // Assert that the values match expected values
        assertEq(frontendFeeStored, frontendFeeAmount);
        assertEq(incentiveAmountStored, incentiveAmount);
        assertEq(protocolFeeAmountStored, protocolFeeAmount);

        // Ensure the transfer was successful
        assertEq(MockERC20(address(mockIncentiveToken)).balanceOf(address(recipeMarketHub)), protocolFeeAmount + frontendFeeAmount + incentiveAmount);
    }

    function test_CreateIPOffer_ForPointsProgram() external {
        bytes32 marketHash = createMarket();

        Points points = pointsFactory.createPointsProgram("POINTS", "PTS", 18, BOB_ADDRESS);
        vm.startPrank(BOB_ADDRESS);
        points.addAllowedIP(ALICE_ADDRESS);
        vm.stopPrank();

        // Handle minting incentive token to the IP's address
        address[] memory tokensOffered = new address[](1);
        tokensOffered[0] = address(points);
        uint256[] memory incentiveAmountsOffered = new uint256[](1);
        incentiveAmountsOffered[0] = 1000e18;

        uint256 quantity = 100_000e18; // The amount of input tokens to be deposited
        uint256 expiry = block.timestamp + 1 days; // Offer expires in 1 day

        // Calculate expected fees
        (,,, uint256 frontendFee,,,) = recipeMarketHub.marketHashToWeirollMarket(marketHash);
        uint256 incentiveAmount = incentiveAmountsOffered[0].divWadDown(1e18 + recipeMarketHub.protocolFee() + frontendFee);
        uint256 protocolFeeAmount = incentiveAmount.mulWadDown(recipeMarketHub.protocolFee());
        uint256 frontendFeeAmount = incentiveAmount.mulWadDown(frontendFee);

        vm.expectEmit(false, false, false, false, address(recipeMarketHub));
        emit RecipeMarketHubBase.IPOfferCreated(
            0, // Expected offer ID (starts at 0)
            bytes32(0),
            marketHash, // Market ID
            quantity, // Total quantity
            tokensOffered, // Tokens offered
            incentiveAmountsOffered, // Amounts offered
            new uint256[](0),
            new uint256[](0),
            expiry // Expiry time
        );

        vm.startPrank(ALICE_ADDRESS);
        // Create the IP offer
        bytes32 offerHash = recipeMarketHub.createIPOffer(
            marketHash, // Referencing the created market
            quantity, // Total input token amount
            expiry, // Expiry time
            tokensOffered, // Incentive tokens offered
            incentiveAmountsOffered // Incentive amounts offered
        );
        vm.stopPrank();

        // Assertions on the offer
        assertEq(recipeMarketHub.numIPOffers(), 1); // IP offer count should be 1
        assertEq(recipeMarketHub.numAPOffers(), 0); // AP offers should remain 0

        // Use the helper function to retrieve values from storage
        uint256 frontendFeeStored = recipeMarketHub.getIncentiveToFrontendFeeAmountForIPOffer(offerHash, tokensOffered[0]);
        uint256 protocolFeeAmountStored = recipeMarketHub.getIncentiveToProtocolFeeAmountForIPOffer(offerHash, tokensOffered[0]);
        uint256 incentiveAmountStored = recipeMarketHub.getIncentiveAmountsOfferedForIPOffer(offerHash, tokensOffered[0]);

        // Assert that the values match expected values
        assertEq(frontendFeeStored, frontendFeeAmount);
        assertEq(incentiveAmountStored, incentiveAmount);
        assertEq(protocolFeeAmountStored, protocolFeeAmount);
    }

    function test_RevertIf_CreateIPOfferWithNonExistentMarket() external {
        vm.expectRevert(abi.encodeWithSelector(RecipeMarketHubBase.MarketDoesNotExist.selector));
        recipeMarketHub.createIPOffer(
            0, // Non-existent market ID
            100_000e18, // Quantity
            block.timestamp + 1 days, // Expiry time
            new address[](1), // Empty tokens offered array
            new uint256[](1) // Empty token amounts array
        );
    }

    function test_RevertIf_CreateIPOfferWithExpiredOffer() external {
        vm.warp(1_231_006_505); // set block timestamp
        bytes32 marketHash = createMarket();
        vm.expectRevert(abi.encodeWithSelector(RecipeMarketHubBase.CannotPlaceExpiredOffer.selector));
        recipeMarketHub.createIPOffer(
            marketHash,
            100_000e18, // Quantity
            block.timestamp - 1 seconds, // Expired timestamp
            new address[](1), // Empty tokens offered array
            new uint256[](1) // Empty token amounts array
        );
    }

    function test_RevertIf_CreateIPOfferWithZeroQuantity() external {
        bytes32 marketHash = createMarket();
        vm.expectRevert(abi.encodeWithSelector(RecipeMarketHubBase.CannotPlaceZeroQuantityOffer.selector));
        recipeMarketHub.createIPOffer(
            marketHash,
            0, // Zero quantity
            block.timestamp + 1 days, // Expiry time
            new address[](1), // Empty tokens offered array
            new uint256[](1) // Empty token amounts array
        );
    }

    function test_RevertIf_CreateIPOfferWithMismatchedTokenArrays() external {
        bytes32 marketHash = createMarket();

        address[] memory tokensOffered = new address[](1);
        tokensOffered[0] = address(mockIncentiveToken);
        uint256[] memory incentiveAmountsOffered = new uint256[](2);
        incentiveAmountsOffered[0] = 1000e18;

        vm.expectRevert(abi.encodeWithSelector(RecipeMarketHubBase.ArrayLengthMismatch.selector));
        recipeMarketHub.createIPOffer(
            marketHash,
            100_000e18, // Quantity
            block.timestamp + 1 days, // Expiry time
            tokensOffered, // Mismatched arrays
            incentiveAmountsOffered
        );
    }
}
