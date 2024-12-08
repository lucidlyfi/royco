// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { console } from "lib/forge-std/src/console.sol";
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

    function getDenom(bytes32 offerHash) external view returns (uint256) {
        int256 maxIntValue = type(int256).max; // 2**255 - 1
        int256 maxAllowed = 135_305_999_368_893_231_588; // because `expWad(x)` reverts at x >= 135305999368893231589
        int256 decayRate = offerHashToIPGdaOffer[offerHash].gdaParams.decayRate;
        int256 lastAuctionStartTime = offerHashToIPGdaOffer[offerHash].gdaParams.lastAuctionStartTime;
        int256 timeSinceLastAuctionStart = SafeCastLib.toInt256(block.timestamp) - lastAuctionStartTime;
        int256 denInt = expWad(sMulWad(decayRate, timeSinceLastAuctionStart));
        return SafeCastLib.toUint256(denInt);
    }

    function getIncentiveAmountsOfferedForIPGdaOffer(bytes32 offerHash, address tokenAddress, uint256 fillAmount) external view returns (uint256) {
        uint256 incentiveMultiplier = GradualDutchAuction._calculateIncentiveMultiplier(
            offerHashToIPGdaOffer[offerHash].gdaParams.decayRate,
            offerHashToIPGdaOffer[offerHash].gdaParams.emissionRate,
            offerHashToIPGdaOffer[offerHash].gdaParams.lastAuctionStartTime,
            fillAmount
        );
        console.log("incentiveMultiplier:", incentiveMultiplier);
        uint256 initialIncentivesOffered = offerHashToIPGdaOffer[offerHash].initialIncentiveAmountsOffered[tokenAddress];
        uint256 minMultiplier = 1e18;
        uint256 maxMultiplier = FixedPointMathLib.divWadDown(
            offerHashToIPGdaOffer[offerHash].incentiveAmountsOffered[tokenAddress],
            offerHashToIPGdaOffer[offerHash].initialIncentiveAmountsOffered[tokenAddress]
        );
        uint256 scaledMultiplier =
            minMultiplier + FixedPointMathLib.divWadDown(FixedPointMathLib.mulWadDown(incentiveMultiplier, maxMultiplier - minMultiplier), maxMultiplier);
        console.log("scaledMultiplier:", scaledMultiplier);
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

    /// @dev Returns `exp(x)`, denominated in `WAD`.
    /// Credit to Remco Bloemen under MIT license: https://2π.com/22/exp-ln
    /// Note: This function is an approximation. Monotonically increasing.
    function expWad(int256 x) internal pure returns (int256 r) {
        unchecked {
            // When the result is less than 0.5 we return zero.
            // This happens when `x <= (log(1e-18) * 1e18) ~ -4.15e19`.
            if (x <= -41_446_531_673_892_822_313) return r;

            /// @solidity memory-safe-assembly
            assembly {
                // When the result is greater than `(2**255 - 1) / 1e18` we can not represent it as
                // an int. This happens when `x >= floor(log((2**255 - 1) / 1e18) * 1e18) ≈ 135`.
                if iszero(slt(x, 135305999368893231589)) {
                    mstore(0x00, 0xa37bfec9) // `ExpOverflow()`.
                    revert(0x1c, 0x04)
                }
            }

            // `x` is now in the range `(-42, 136) * 1e18`. Convert to `(-42, 136) * 2**96`
            // for more intermediate precision and a binary basis. This base conversion
            // is a multiplication by 1e18 / 2**96 = 5**18 / 2**78.
            x = (x << 78) / 5 ** 18;

            // Reduce range of x to (-½ ln 2, ½ ln 2) * 2**96 by factoring out powers
            // of two such that exp(x) = exp(x') * 2**k, where k is an integer.
            // Solving this gives k = round(x / log(2)) and x' = x - k * log(2).
            int256 k = ((x << 96) / 54_916_777_467_707_473_351_141_471_128 + 2 ** 95) >> 96;
            x = x - k * 54_916_777_467_707_473_351_141_471_128;

            // `k` is in the range `[-61, 195]`.

            // Evaluate using a (6, 7)-term rational approximation.
            // `p` is made monic, we'll multiply by a scale factor later.
            int256 y = x + 1_346_386_616_545_796_478_920_950_773_328;
            y = ((y * x) >> 96) + 57_155_421_227_552_351_082_224_309_758_442;
            int256 p = y + x - 94_201_549_194_550_492_254_356_042_504_812;
            p = ((p * y) >> 96) + 28_719_021_644_029_726_153_956_944_680_412_240;
            p = p * x + (4_385_272_521_454_847_904_659_076_985_693_276 << 96);

            // We leave `p` in `2**192` basis so we don't need to scale it back up for the division.
            int256 q = x - 2_855_989_394_907_223_263_936_484_059_900;
            q = ((q * x) >> 96) + 50_020_603_652_535_783_019_961_831_881_945;
            q = ((q * x) >> 96) - 533_845_033_583_426_703_283_633_433_725_380;
            q = ((q * x) >> 96) + 3_604_857_256_930_695_427_073_651_918_091_429;
            q = ((q * x) >> 96) - 14_423_608_567_350_463_180_887_372_962_807_573;
            q = ((q * x) >> 96) + 26_449_188_498_355_588_339_934_803_723_976_023;

            /// @solidity memory-safe-assembly
            assembly {
                // Div in assembly because solidity adds a zero check despite the unchecked.
                // The q polynomial won't have zeros in the domain as all its roots are complex.
                // No scaling is necessary because p is already `2**96` too large.
                r := sdiv(p, q)
            }

            // r should be in the range `(0.09, 0.25) * 2**96`.

            // We now need to multiply r by:
            // - The scale factor `s ≈ 6.031367120`.
            // - The `2**k` factor from the range reduction.
            // - The `1e18 / 2**96` factor for base conversion.
            // We do this all at once, with an intermediate result in `2**213`
            // basis, so the final right shift is always by a positive amount.
            r = int256((uint256(r) * 3_822_833_074_963_236_453_042_738_258_902_158_003_155_416_615_667) >> uint256(195 - k));
        }
    }

    /// @dev Equivalent to `(x * y) / WAD` rounded down.
    function sMulWad(int256 x, int256 y) internal pure returns (int256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            z := mul(x, y)
            // Equivalent to `require((x == 0 || z / x == y) && !(x == -1 && y == type(int256).min))`.
            if iszero(gt(or(iszero(x), eq(sdiv(z, x), y)), lt(not(x), eq(y, shl(255, 1))))) {
                mstore(0x00, 0xedcd4dd4) // `SMulWadFailed()`.
                revert(0x1c, 0x04)
            }
            z := sdiv(z, WAD)
        }
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
