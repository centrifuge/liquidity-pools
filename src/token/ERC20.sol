// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {Auth} from "src/Auth.sol";
import {EIP712Lib} from "src/libraries/EIP712Lib.sol";
import {SignatureLib} from "src/libraries/SignatureLib.sol";
import {IERC20, IERC20Metadata, IERC20Permit} from "src/interfaces/IERC20.sol";

/// @title  ERC20
/// @notice Standard ERC-20 implementation, with mint/burn functionality and permit logic.
/// @author Modified from https://github.com/makerdao/xdomain-dss/blob/master/src/Dai.sol
contract ERC20 is Auth, IERC20Metadata, IERC20Permit {
    /// @inheritdoc IERC20Metadata
    string public name;
    /// @inheritdoc IERC20Metadata
    string public symbol;
    /// @inheritdoc IERC20Metadata
    uint8 public immutable decimals;
    /// @inheritdoc IERC20
    uint256 public totalSupply;

    mapping(address => uint256) internal balances;
    /// @inheritdoc IERC20
    mapping(address => mapping(address => uint256)) public allowance;
    /// @inheritdoc IERC20Permit
    mapping(address => uint256) public nonces;

    // --- EIP712 ---
    bytes32 private immutable nameHash;
    bytes32 private immutable versionHash;
    uint256 public immutable deploymentChainId;
    bytes32 private immutable _DOMAIN_SEPARATOR;
    bytes32 public constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    // --- Events ---
    event File(bytes32 indexed what, string data);

    constructor(uint8 decimals_) {
        decimals = decimals_;
        wards[msg.sender] = 1;
        emit Rely(msg.sender);

        nameHash = keccak256(bytes("Centrifuge"));
        versionHash = keccak256(bytes("1"));
        deploymentChainId = block.chainid;
        _DOMAIN_SEPARATOR = EIP712Lib.calculateDomainSeparator(nameHash, versionHash);
    }

    /// @inheritdoc IERC20
    function balanceOf(address user) public view virtual returns (uint256) {
        return balances[user];
    }

    function _setBalance(address user, uint256 value) internal {
        balances[user] = value;
    }

    /// @inheritdoc IERC20Permit
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return block.chainid == deploymentChainId
            ? _DOMAIN_SEPARATOR
            : EIP712Lib.calculateDomainSeparator(nameHash, versionHash);
    }

    // --- Administration ---
    function file(bytes32 what, string memory data) public virtual auth {
        if (what == "name") name = data;
        else if (what == "symbol") symbol = data;
        else revert("ERC20/file-unrecognized-param");
        emit File(what, data);
    }

    // --- ERC20 Mutations ---
    /// @inheritdoc IERC20
    function transfer(address to, uint256 value) public virtual returns (bool) {
        require(to != address(0) && to != address(this), "ERC20/invalid-address");
        uint256 balance = balanceOf(msg.sender);
        require(balance >= value, "ERC20/insufficient-balance");

        unchecked {
            balances[msg.sender] -= value;
            balances[to] += value; // note: we don't need an overflow check here b/c sum of all balances == totalSupply
        }

        emit Transfer(msg.sender, to, value);

        return true;
    }

    /// @inheritdoc IERC20
    function transferFrom(address from, address to, uint256 value) public virtual returns (bool) {
        return _transferFrom(msg.sender, from, to, value);
    }

    function _transferFrom(address sender, address from, address to, uint256 value) internal virtual returns (bool) {
        require(to != address(0) && to != address(this), "ERC20/invalid-address");
        uint256 balance = balanceOf(from);
        require(balance >= value, "ERC20/insufficient-balance");

        if (from != sender) {
            uint256 allowed = allowance[from][sender];
            if (allowed != type(uint256).max) {
                require(allowed >= value, "ERC20/insufficient-allowance");
                unchecked {
                    allowance[from][sender] = allowed - value;
                }
            }
        }

        unchecked {
            balances[from] -= value;
            balances[to] += value; // note: we don't need an overflow check here b/c sum of all balances == totalSupply
        }

        emit Transfer(from, to, value);

        return true;
    }

    /// @inheritdoc IERC20
    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;

        emit Approval(msg.sender, spender, value);

        return true;
    }

    // --- Mint/Burn ---
    function mint(address to, uint256 value) public virtual auth {
        require(to != address(0) && to != address(this), "ERC20/invalid-address");
        unchecked {
            // We don't need an overflow check here b/c balances[to] <= totalSupply
            // and there is an overflow check below
            balances[to] += value;
        }
        totalSupply = totalSupply + value;

        emit Transfer(address(0), to, value);
    }

    function burn(address from, uint256 value) public virtual auth {
        uint256 balance = balanceOf(from);
        require(balance >= value, "ERC20/insufficient-balance");

        if (from != msg.sender) {
            uint256 allowed = allowance[from][msg.sender];
            if (allowed != type(uint256).max) {
                require(allowed >= value, "ERC20/insufficient-allowance");

                unchecked {
                    allowance[from][msg.sender] = allowed - value;
                }
            }
        }

        unchecked {
            // We don't need overflow checks b/c require(balance >= value) and balance <= totalSupply
            balances[from] -= value;
            totalSupply = totalSupply - value;
        }

        emit Transfer(from, address(0), value);
    }

    // --- Approve by signature ---
    function permit(address owner, address spender, uint256 value, uint256 deadline, bytes memory signature) public {
        require(block.timestamp <= deadline, "ERC20/permit-expired");
        require(owner != address(0), "ERC20/invalid-owner");

        uint256 nonce;
        unchecked {
            nonce = nonces[owner]++;
        }

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR(),
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonce, deadline))
            )
        );

        require(SignatureLib.isValidSignature(owner, digest, signature), "ERC20/invalid-permit");

        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    /// @inheritdoc IERC20Permit
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
    {
        permit(owner, spender, value, deadline, abi.encodePacked(r, s, v));
    }
}
