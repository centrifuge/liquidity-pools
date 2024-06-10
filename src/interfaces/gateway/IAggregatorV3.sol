// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

interface IAggregatorV3 {
    /// @notice TODO Documenation
    function decimals() external view returns (uint8);

    /// @notice TODO Documenation
    function description() external view returns (string memory);

    /// @notice TODO Documenation
    function version() external view returns (uint256);

    /// @notice TODO Documenation
    function getRoundData(uint80 _roundId)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt);

    /// @notice TODO Documenation
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt);
}
