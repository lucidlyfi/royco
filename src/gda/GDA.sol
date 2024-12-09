// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { RecipeMarketHubBase, RewardStyle, WeirollWallet } from "src/base/RecipeMarketHubBase.sol";
import { ERC20 } from "lib/solmate/src/tokens/ERC20.sol";
import { ERC4626 } from "lib/solmate/src/tokens/ERC4626.sol";
import { ClonesWithImmutableArgs } from "lib/clones-with-immutable-args/src/ClonesWithImmutableArgs.sol";
import { SafeTransferLib } from "lib/solmate/src/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "lib/solady/src/utils/FixedPointMathLib.sol";
import { SafeCastLib } from "lib/solady/src/utils/SafeCastLib.sol";
import { Points } from "src/Points.sol";
import { PointsFactory } from "src/PointsFactory.sol";
import { Owned } from "lib/solmate/src/auth/Owned.sol";

library GradualDutchAuction {
    function _calculateIncentiveMultiplier(
        int256 decayRate,
        int256 emissionRate,
        int256 lastAuctionStartTime,
        uint256 numTokens
    )
        internal
        view
        returns (uint256)
    {
        int256 maxIntValue = type(int256).max; // 2**255 - 1
        int256 maxAllowed = 135_305_999_368_893_231_588; // because `expWad(x)` reverts at x >= 135305999368893231589
        int256 quantity = SafeCastLib.toInt256(numTokens);
        int256 timeSinceLastAuctionStart = SafeCastLib.toInt256(block.timestamp) - lastAuctionStartTime;
        int256 num1 = FixedPointMathLib.rawSDivWad(1e18, decayRate);

        // exponent = e^((((decayRate * quantity) / emissionRate ) * maxAllowed)/ maxIntValue) - 1
        int256 exponent = FixedPointMathLib.expWad(
            FixedPointMathLib.sDivWad(
                FixedPointMathLib.sMulWad(FixedPointMathLib.sDivWad(FixedPointMathLib.sMulWad(decayRate, quantity), emissionRate), maxAllowed), maxIntValue
            )
        ) - 1;

        //  den = e^(decayRate / timeSinceLastAuctionStart)
        int256 den = FixedPointMathLib.expWad(FixedPointMathLib.rawSDiv(decayRate, timeSinceLastAuctionStart));
        int256 totalIncentiveMultiplier = FixedPointMathLib.sDivWad(FixedPointMathLib.sMulWad(num1, exponent), den);
        return SafeCastLib.toUint256(FixedPointMathLib.lnWad(totalIncentiveMultiplier + 1e18));
    }

    function _expWad(int256 x) internal view returns (int256) {
        return FixedPointMathLib.expWad(x);
    }
}
