// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// OpenZeppelin upgradeable imports.
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

/// @title EmergencyUtils - Contract to manage emergency utilities and functionalities
/// @dev This contract should be inherited by other contracts that require emergency functionalities.
/// It uses namespaced storage to avoid collisions and allow extendability.
contract EmergencyUtils is OwnableUpgradeable, PausableUpgradeable, AccessControlUpgradeable {
  using SafeERC20 for IERC20;

  /////////////////
  /// Constants ///
  /////////////////

  /// @dev keccak256(abi.encode(uint256(keccak256("pareto.storage.EmergencyUtils")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant EmergencyUtilsStorageLocation = 0x34255c687a9ae703b4ae30638c7776ee81513fdfa4b4dd654e5578b21b95d800;
  /// @notice role for pausing the contract
  bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

  //////////////////////
  /// Storage Layout ///
  //////////////////////

  /// @custom:storage-location erc7201:pareto.storage.EmergencyUtils
  struct EmergencyUtilsStorage {
    // This is used as a placeholder so to be able to declare the struct
    bool _isPausable; 
  }

  //////////////////////////
  /// Initialize methods ///
  //////////////////////////

  /// @param _owner The owner address.
  /// @param _admin The admin address.
  /// @param _pauser The pauser address.
  function __EmergencyUtils_init(address _owner, address _admin, address _pauser) internal onlyInitializing {
    // Initialize inherited contracts
    __Ownable_init(_owner);
    __Pausable_init();
    __AccessControl_init();

    // manage roles
    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    _grantRole(PAUSER_ROLE, _admin);
    _grantRole(PAUSER_ROLE, _pauser);

    // set storage
    EmergencyUtilsStorage storage $ = _getEmergencyUtilsStorage();
    $._isPausable = true;
  }

  //////////////////////
  /// View functions ///
  //////////////////////

  /// @notice Check if the contract is pausable.
  /// @return True if the contract is pausable, false otherwise.
  function isPausable() public view virtual returns (bool) {
    EmergencyUtilsStorage storage $ = _getEmergencyUtilsStorage();
    return $._isPausable;
  }

  //////////////////////////
  /// Internal functions ///
  //////////////////////////

  /// @dev Get the storage location for EmergencyUtils.
  /// @return $ The storage location for EmergencyUtils.
  function _getEmergencyUtilsStorage() private pure returns (EmergencyUtilsStorage storage $) {
    assembly {
      $.slot := EmergencyUtilsStorageLocation
    }
  }

  ///////////////////////
  /// Admin functions ///
  ///////////////////////

  /// @notice Emergency function for the owner to withdraw collateral tokens.
  /// @param token The collateral token address.
  /// @param amount The amount to withdraw.
  function emergencyWithdraw(address token, uint256 amount) public virtual {
    _checkOwner();
    IERC20(token).safeTransfer(msg.sender, amount);
  }

  /// @notice Pauser can pause the contract in emergencies.
  function pause() external {
    _checkRole(PAUSER_ROLE);
    _pause();
  }

  /// @notice Owner can unpause the contract.
  function unpause() external {
    _checkOwner();
    _unpause();
  }
}
