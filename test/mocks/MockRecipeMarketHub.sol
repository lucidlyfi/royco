// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { RecipeMarketHub } from "src/RecipeMarketHub.sol";
import { RecipeMarketHubBase, RewardStyle, WeirollWallet } from "src/base/RecipeMarketHubBase.sol";
import { ERC20 } from "lib/solmate/src/tokens/ERC20.sol";
import { ERC4626 } from "lib/solmate/src/tokens/ERC4626.sol";
import { ClonesWithImmutableArgs } from "lib/clones-with-immutable-args/src/ClonesWithImmutableArgs.sol";
import { Owned } from "lib/solmate/src/auth/Owned.sol";
import { SafeTransferLib } from "lib/solmate/src/utils/SafeTransferLib.sol";
import { SafeCastLib } from "lib/solady/src/utils/SafeCastLib.sol";
import { FixedPointMathLib } from "lib/solmate/src/utils/FixedPointMathLib.sol";
import { Points } from "src/Points.sol";
import { PointsFactory } from "src/PointsFactory.sol";
import { GradualDutchAuction } from "src/gda/GDA.sol";

contract MockRecipeMarketHub is RecipeMarketHub {
    constructor(
        address _weirollWalletImplementation,
        uint256 _protocolFee,
        uint256 _minimumFrontendFee,
        address _owner,
        address _pointsFactory
    )
        RecipeMarketHub(_weirollWalletImplementation, _protocolFee, _minimumFrontendFee, _owner, _pointsFactory)
    { }

    function fillIPOffers(bytes32 offerHash, uint256 fillAmount, address fundingVault, address frontendFeeRecipient) external {
        _fillIPOffer(offerHash, fillAmount, fundingVault, frontendFeeRecipient);
    }

    function fillIPGdaOffers(bytes32 offerHash, uint256 fillAmount, address fundingVault, address frontendFeeRecipient) external {
        _fillIPGdaOffer(offerHash, fillAmount, fundingVault, frontendFeeRecipient);
    }

    function fillAPOffers(APOffer calldata offer, uint256 fillAmount, address frontendFeeRecipient) external {
        _fillAPOffer(offer, fillAmount, frontendFeeRecipient);
    }

    // Getters to access nested mappings
    function getIncentiveAmountsOfferedForIPOffer(bytes32 offerHash, address tokenAddress) external view returns (uint256) {
        return offerHashToIPOffer[offerHash].incentiveAmountsOffered[tokenAddress];
    }

    function getMaxIncentiveAmountsOfferedForIPGdaOffer(bytes32 offerHash, address tokenAddress) external view returns (uint256) {
        return offerHashToIPGdaOffer[offerHash].incentiveAmountsOffered[tokenAddress];
    }

    function getMinIncentiveAmountsOfferedForIPGdaOffer(bytes32 offerHash, address tokenAddress) external view returns (uint256) {
        return offerHashToIPGdaOffer[offerHash].initialIncentiveAmountsOffered[tokenAddress];
    }

    function getLastAuctionStartTime(bytes32 offerHash) external view returns (uint256) {
        int256 lastAuctionStartTime = offerHashToIPGdaOffer[offerHash].gdaParams.lastAuctionStartTime;
        return SafeCastLib.toUint256(lastAuctionStartTime);
    }

    function getIncentiveAmountsOfferedForIPGdaOffer(bytes32 offerHash, address tokenAddress, uint256 fillAmount) external view returns (uint256) {
        uint256 fillPercentage = FixedPointMathLib.divWadDown(fillAmount, offerHashToIPGdaOffer[offerHash].quantity);
        uint256 incentiveMultiplier = GradualDutchAuction._calculateIncentiveMultiplier(
            offerHashToIPGdaOffer[offerHash].gdaParams.decayRate,
            offerHashToIPGdaOffer[offerHash].gdaParams.emissionRate,
            offerHashToIPGdaOffer[offerHash].gdaParams.lastAuctionStartTime,
            fillPercentage
        );
        uint256 initialIncentivesOffered = offerHashToIPGdaOffer[offerHash].initialIncentiveAmountsOffered[tokenAddress];
        uint256 minMultiplier = 1e18;
        uint256 maxMultiplier = FixedPointMathLib.divWadDown(
            offerHashToIPGdaOffer[offerHash].incentiveAmountsOffered[tokenAddress],
            offerHashToIPGdaOffer[offerHash].initialIncentiveAmountsOffered[tokenAddress]
        );

        uint256 maxAllowed = 135_305_999_368_893_231_588;
        uint256 scaledMultiplier =
            minMultiplier + FixedPointMathLib.divWadDown(FixedPointMathLib.mulWadDown(incentiveMultiplier, maxMultiplier - minMultiplier), maxAllowed);
        return FixedPointMathLib.mulWadDown(initialIncentivesOffered, scaledMultiplier);
    }

    function getIncentiveToProtocolFeeAmountForIPOffer(bytes32 offerHash, address tokenAddress) external view returns (uint256) {
        return offerHashToIPOffer[offerHash].incentiveToProtocolFeeAmount[tokenAddress];
    }

    function getIncentiveToProtocolFeeAmountForIPGdaOffer(bytes32 offerHash, address tokenAddress) external view returns (uint256) {
        return offerHashToIPGdaOffer[offerHash].incentiveToProtocolFeeAmount[tokenAddress];
    }

    function getIncentiveToFrontendFeeAmountForIPOffer(bytes32 offerHash, address tokenAddress) external view returns (uint256) {
        return offerHashToIPOffer[offerHash].incentiveToFrontendFeeAmount[tokenAddress];
    }

    function getIncentiveToFrontendFeeAmountForIPGdaOffer(bytes32 offerHash, address tokenAddress) external view returns (uint256) {
        return offerHashToIPGdaOffer[offerHash].incentiveToFrontendFeeAmount[tokenAddress];
    }

    // Single getter function that returns the entire LockedRewardParams struct as a tuple
    function getLockedIncentiveParams(address weirollWallet) external view returns (address[] memory incentives, uint256[] memory amounts, address ip) {
        LockedRewardParams storage params = weirollWalletToLockedIncentivesParams[weirollWallet];
        return (params.incentives, params.amounts, params.ip);
    }

    /// @notice Calculates the hash of an AP offer
    function getOfferHash(APOffer memory offer) public pure returns (bytes32) {
        return keccak256(abi.encode(offer));
    }

    /// @notice Calculates the hash of an IP offer
    function getOfferHash(
        uint256 offerID,
        bytes32 targetMarketHash,
        address ip,
        uint256 expiry,
        uint256 quantity,
        address[] calldata incentivesOffered,
        uint256[] memory incentiveAmountsOffered
    )
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(offerID, targetMarketHash, ip, expiry, quantity, incentivesOffered, incentiveAmountsOffered));
    }

    uint256 internal constant WAD = 1e18;
}
