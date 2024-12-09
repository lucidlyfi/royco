// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import { Ownable2Step, Ownable } from "../lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import { ERC4626 } from "../lib/solmate/src/tokens/ERC4626.sol";
import { LibString } from "../lib/solmate/src/utils/LibString.sol";
import { Clones } from "../lib/openzeppelin-contracts/contracts/proxy/Clones.sol";
import { WrappedVault } from "./WrappedVault.sol";

/// @title WrappedVaultFactory
/// @author CopyPaste, Jack Corddry, Shivaansh Kapoor
/// @dev A factory for deploying wrapped vaults, and managing protocol or other fees
contract WrappedVaultFactory is Ownable2Step {
    using Clones for address;

    // Address of the Wrapped Vault's implementation contract
    address wrappedVaultImplementation;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(
        address _wrappedVaultImplementation,
        address _protocolFeeRecipient,
        uint256 _protocolFee,
        uint256 _minimumFrontendFee,
        address _owner,
        address _pointsFactory
    )
        payable
        Ownable(_owner)
    {
        if (_wrappedVaultImplementation.code.length == 0) revert InvalidWrappedVaultImplementation();
        if (_protocolFee > MAX_PROTOCOL_FEE) revert ProtocolFeeTooHigh();
        if (_minimumFrontendFee > MAX_MIN_REFERRAL_FEE) revert ReferralFeeTooHigh();

        wrappedVaultImplementation = _wrappedVaultImplementation;
        protocolFeeRecipient = _protocolFeeRecipient;
        protocolFee = _protocolFee;
        minimumFrontendFee = _minimumFrontendFee;
        pointsFactory = _pointsFactory;
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 public constant MAX_PROTOCOL_FEE = 0.3e18;
    uint256 public constant MAX_MIN_REFERRAL_FEE = 0.3e18;

    address public immutable pointsFactory;

    address public protocolFeeRecipient;

    /// @dev The protocolFee for all incentivized vaults
    uint256 public protocolFee;
    /// @dev The default minimumFrontendFee to initialize incentivized vaults with
    uint256 public minimumFrontendFee;

    /// @dev All incentivized vaults deployed by this factory
    address[] public incentivizedVaults;
    mapping(address => bool) public isVault;

    /*//////////////////////////////////////////////////////////////
                               INTERFACE
    //////////////////////////////////////////////////////////////*/
    error InvalidWrappedVaultImplementation();
    error ProtocolFeeTooHigh();
    error ReferralFeeTooHigh();

    event WrappedVaultImplementationUpdated(address newWrappedVaultImplementation);
    event ProtocolFeeUpdated(uint256 newProtocolFee);
    event ReferralFeeUpdated(uint256 newReferralFee);
    event ProtocolFeeRecipientUpdated(address newRecipient);
    event WrappedVaultCreated(
        ERC4626 indexed underlyingVaultAddress,
        WrappedVault indexed incentivizedVaultAddress,
        address owner,
        address inputToken,
        uint256 frontendFee,
        string name,
        string vaultSymbol
    );

    /*//////////////////////////////////////////////////////////////
                             OWNER CONTROLS
    //////////////////////////////////////////////////////////////*/

    /// @param newWrappedVaultImplementation The new address of the Wrapped Vault implementation.
    function updateWrappedVaultImplementation(address newWrappedVaultImplementation) external payable onlyOwner {
        if (newWrappedVaultImplementation.code.length == 0) revert InvalidWrappedVaultImplementation();
        wrappedVaultImplementation = newWrappedVaultImplementation;
        emit WrappedVaultImplementationUpdated(newWrappedVaultImplementation);
    }

    /// @param newProtocolFee The new protocol fee to set for a given vault, must be less than MAX_PROTOCOL_FEE
    function updateProtocolFee(uint256 newProtocolFee) external payable onlyOwner {
        if (newProtocolFee > MAX_PROTOCOL_FEE) revert ProtocolFeeTooHigh();
        protocolFee = newProtocolFee;
        emit ProtocolFeeUpdated(newProtocolFee);
    }

    /// @param newMinimumReferralFee The new minimum referral fee to set for all incentivized vaults, must be less than MAX_MIN_REFERRAL_FEE
    function updateMinimumReferralFee(uint256 newMinimumReferralFee) external payable onlyOwner {
        if (newMinimumReferralFee > MAX_MIN_REFERRAL_FEE) revert ReferralFeeTooHigh();
        minimumFrontendFee = newMinimumReferralFee;
        emit ReferralFeeUpdated(newMinimumReferralFee);
    }

    /// @param newRecipient The new protocol fee recipient to set for all incentivized vaults
    function updateProtocolFeeRecipient(address newRecipient) external payable onlyOwner {
        protocolFeeRecipient = newRecipient;
        emit ProtocolFeeRecipientUpdated(newRecipient);
    }

    /*//////////////////////////////////////////////////////////////
                             VAULT CREATION
    //////////////////////////////////////////////////////////////*/

    /// @param vault The ERC4626 Vault to wrap.
    /// @param owner The address of the wrapped vault owner.
    /// @param name The name of the wrapped vault.
    /// @param initialFrontendFee The initial frontend fee for the wrapped vault.
    function wrapVault(ERC4626 vault, address owner, string calldata name, uint256 initialFrontendFee) external payable returns (WrappedVault wrappedVault) {
        string memory newSymbol = getNextSymbol();
        bytes32 salt = keccak256(abi.encodePacked(address(vault), owner, name, initialFrontendFee));
        wrappedVault = WrappedVault(wrappedVaultImplementation.cloneDeterministic(salt));
        wrappedVault.initialize(owner, name, newSymbol, address(vault), initialFrontendFee, pointsFactory);

        incentivizedVaults.push(address(wrappedVault));
        isVault[address(wrappedVault)] = true;

        emit WrappedVaultCreated(vault, wrappedVault, owner, address(wrappedVault.asset()), initialFrontendFee, name, newSymbol);
    }

    /// @dev Helper function to get the symbol for a new incentivized vault, ROY-0, ROY-1, etc.
    function getNextSymbol() internal view returns (string memory) {
        return string.concat("ROY-", LibString.toString(incentivizedVaults.length));
    }
}
