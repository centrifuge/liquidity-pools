// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

interface IGasService {
    event File(bytes32 what, uint256 value);

    /// Using file patter to update state variables;
    /// @dev Used to update the messageCost and proofCost;
    function file(bytes32 what, uint256 value) external;

    /// The cost of 'message' execution on Destination chain.
    /// @dev This is a getter method
    /// @return Amount in <destination_chain_token>
    function messageCost() external returns (uint256);

    /// The cost of 'proof' execution on Destination chain.
    /// @dev This is a getter method
    /// @return Amount in <destination_chain_token>
    function proofCost() external returns (uint256);

    /// <destination_chain_token>/ETH price
    /// @dev This is a getter method
    /// @return The current price
    function price() external returns (uint256);

    /// Called to update the  <destination_chain_token>/ETH price
    /// @param value -
    function updatePrice(uint256 value) external;

    /// Estimate the total execution cost on destination chain in ETH.abi
    /// @param payload - Estimates the execution cost based on the payload.abi
    /// @return Estimated cost in WEI units
    function estimate(bytes calldata payload) external returns (uint256);

    /// Used to verify if given user for a given message can take advantage of
    /// transaction cost prepayment.
    /// @param source Source that triggered the transaction
    /// @param payload The message that is going to be send
    function shouldRefuel(address source, bytes calldata payload) external view returns (bool);
}
