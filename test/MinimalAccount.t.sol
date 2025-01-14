// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.15;

import "foundry-huff/HuffDeployer.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";
import "account-abstraction/core/EntryPoint.sol";
import "solady/utils/ECDSA.sol";

struct Owner {
    address addr;
    uint256 key;
}

contract MinimalAccountTest is Test {
    MinimalAccount public minimalAccount;
    MinimalAccountFactory public minimalAccountFactory;

    address entrypointAddress = 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789;
    EntryPoint public entryPoint = new EntryPoint();

    Owner owner;

    address bytecodeOwnerAddress = 0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf;

    function setUp() public {
        owner = Owner({key: uint256(1), addr: vm.addr(uint256(1))});
        minimalAccount = MinimalAccount(HuffDeployer.deploy("MinimalAccount"));
        minimalAccountFactory =
            MinimalAccountFactory(HuffDeployer.config().with_evm_version("paris").deploy("MinimalAccountFactory"));

        // Get bytecode of MinimalAccount and MinimalAccountFactory for gas calculations
        // console.logBytes(address(minimalAccount).code);
        console.logBytes(address(minimalAccountFactory).code);
    }

    function testCreateAccount() public {
        address account = minimalAccountFactory.createAccount(bytecodeOwnerAddress, 0);
        assertEq(address(minimalAccount).code, address(account).code);
    }

    function testReceiveETH() public {
        address account = minimalAccountFactory.createAccount(address(this), 0);
        (bool success,) = account.call{value: 1e18}("");
        assertTrue(success);
    }

    function testGetAccountAddress() public {
        address account = minimalAccountFactory.createAccount(address(this), 0);
        address accountAddress = minimalAccountFactory.getAddress(address(this), 0);
        assertEq(account, accountAddress);
    }

    function testValidateUserOp() public {
        address account = minimalAccountFactory.createAccount(owner.addr, 0);
        vm.deal(address(account), 1 ether);

        vm.startPrank(entrypointAddress);
        UserOperation memory userOp = UserOperation({
            sender: minimalAccountFactory.getAddress(address(this), 0),
            nonce: 0,
            initCode: abi.encodePacked(
                address(minimalAccountFactory),
                abi.encodeWithSelector(minimalAccountFactory.createAccount.selector, address(this), 0)
                ),
            callData: abi.encode(address(this), 0, ""),
            callGasLimit: 0,
            verificationGasLimit: 0,
            preVerificationGas: 0,
            maxFeePerGas: 0,
            maxPriorityFeePerGas: 0,
            paymasterAndData: "",
            signature: ""
        });

        bytes32 opHash = entryPoint.getUserOpHash(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(owner.key, ECDSA.toEthSignedMessageHash(opHash));
        bytes memory signature = abi.encodePacked(v, r, s);
        userOp.signature = signature;

        uint256 missingAccountFunds = 420 wei;
        uint256 returnValue = MinimalAccount(account).validateUserOp(userOp, opHash, missingAccountFunds);
        assertEq(returnValue, 0);
        assertEq(entrypointAddress.balance, missingAccountFunds);
        vm.stopPrank();
    }

    function testValidateUserOpDifferentOwner() public {
        vm.startPrank(entrypointAddress);
        uint256 newKey = 2;
        address newOwner = vm.addr(newKey);

        address account = minimalAccountFactory.createAccount(newOwner, 0);
        vm.deal(address(account), 1 ether);

        UserOperation memory userOp = UserOperation({
            sender: minimalAccountFactory.getAddress(newOwner, 0),
            nonce: 0,
            initCode: abi.encodePacked(
                address(minimalAccountFactory),
                abi.encodeWithSelector(minimalAccountFactory.createAccount.selector, newOwner, 0)
                ),
            callData: abi.encode(address(this), 1 wei, ""),
            callGasLimit: 0,
            verificationGasLimit: 0,
            preVerificationGas: 0,
            maxFeePerGas: 0,
            maxPriorityFeePerGas: 0,
            paymasterAndData: "",
            signature: ""
        });

        bytes32 opHash = entryPoint.getUserOpHash(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(newKey, ECDSA.toEthSignedMessageHash(opHash));
        bytes memory signature = abi.encodePacked(v, r, s);
        userOp.signature = signature;

        uint256 missingAccountFunds = 420 wei;
        uint256 returnValue = MinimalAccount(account).validateUserOp(userOp, opHash, missingAccountFunds);
        assertEq(returnValue, 0);
        assertEq(entrypointAddress.balance, missingAccountFunds);
        vm.stopPrank();
    }

    function testValidateUserOp__RervertWhen__NotFromEntrypoint() public {
        vm.startPrank(address(0x69));
        vm.deal(address(minimalAccount), 1 ether);
        UserOperation memory userOp = UserOperation({
            sender: address(this),
            nonce: 0,
            initCode: abi.encodePacked(
                address(minimalAccountFactory),
                abi.encodeWithSelector(minimalAccountFactory.createAccount.selector, address(this), 0)
                ),
            callData: abi.encode(address(this), 0, ""),
            callGasLimit: 0,
            verificationGasLimit: 0,
            preVerificationGas: 0,
            maxFeePerGas: 0,
            maxPriorityFeePerGas: 0,
            paymasterAndData: "",
            signature: ""
        });
        uint256 missingAccountFunds = 420 wei;
        vm.expectRevert();
        uint256 returnValue = minimalAccount.validateUserOp(userOp, "", missingAccountFunds);
        vm.stopPrank();
    }

    function testExecuteValue() public {
        vm.startPrank(entrypointAddress);
        vm.deal(address(minimalAccount), 2 wei);
        address(minimalAccount).call(abi.encode(address(0x69), 1 wei, ""));
        assertEq(address(0x69).balance, 1 wei);
        assertEq(address(minimalAccount).balance, 1 wei);
        vm.stopPrank();
    }

    function testExecuteCalldata() public {
        vm.startPrank(entrypointAddress);
        address(minimalAccount).call(
            abi.encode(
                address(0x69),
                0,
                abi.encodeWithSignature("transfer(address,address,uint256)", address(0x123456), address(0xdeadbeef), 69)
            )
        );
        vm.stopPrank();
    }

    function testExecute__RevertWhen__NotFromEntrypoint() public {
        vm.startPrank(address(0x69));
        vm.expectRevert();
        address(minimalAccount).call(
            abi.encode(
                address(0x69),
                0,
                abi.encodeWithSignature("transfer(address,address,uint256)", address(0x123456), address(0xdeadbeef), 69)
            )
        );
        vm.stopPrank();
    }
}

interface MinimalAccount {
    function validateUserOp(UserOperation calldata, bytes32, uint256) external returns (uint256);
}

interface MinimalAccountFactory {
    function createAccount(address owner, uint256 salt) external returns (address);
    function getAddress(address owner, uint256 salt) external view returns (address);
}
