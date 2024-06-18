// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

interface IGasService {
    event File(bytes32 what, uint64 value);

    /// Using file patter to update state variables;
    /// @dev Used to update the messageCost and proofCost;
    function file(bytes32 what, uint64 value) external;

    /// The cost of 'message' execution on Destination chain.
    /// @dev This is a getter method
    /// @return Amount in Weigth
    function messageCost() external returns (uint64);

    /// The cost of 'proof' execution on Centrifuge chain.
    /// @dev This is a getter method
    /// @return Amount in Weight
    function proofCost() external returns (uint64);

    /// Weigth Gas Price from Centrifuge Chain
    /// @dev This is a getter method
    /// @return The current gas price on Centrifuge chain
    function gasPrice() external returns (uint64);

    /// CFG/ETH price
    /// @dev This is a getter method
    /// @return The current price
    function tokenPrice() external returns (uint256);

    /// Called to update the  gas price
    /// @param value New price in Centrifuge Chain base unit
    function updateGasPrice(uint64 value) external;

    /// Called to update the  CFG/ETH price
    /// @param value New price in wei
    function updateTokenPrice(uint256 value) external;

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
