// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Predeploys } from "../libraries/Predeploys.sol";
import { StandardBridge } from "../universal/StandardBridge.sol";
import { L2StandardBridge } from "../L2/L2StandardBridge.sol";
import { Semver } from "../universal/Semver.sol";

/**
 * @custom:proxied
 * @title L1StandardBridge
 * @notice The L1StandardBridge is responsible for transfering ETH and ERC20 tokens between L1 and
 *         L2. In the case that an ERC20 token is native to L1, it will be escrowed within this
 *         contract. If the ERC20 token is native to L2, it will be burnt. Before Bedrock, ETH was
 *         stored within this contract. After Bedrock, ETH is instead stored inside the
 *         OptimismPortal contract.
 *         NOTE: this contract is not intended to support all variations of ERC20 tokens. Examples
 *         of some token types that may not be properly supported by this contract include, but are
 *         not limited to: tokens with transfer fees, rebasing tokens, and tokens with blocklists.
 */
contract L1StandardBridge is StandardBridge, Semver {
    /**
     * @custom:legacy
     * @notice Emitted whenever a deposit of ETH from L1 into L2 is initiated.
     *
     * @param from      Address of the depositor.
     * @param to        Address of the recipient on L2.
     * @param amount    Amount of ETH deposited.
     * @param extraData Extra data attached to the deposit.
     */
    event ETHDepositInitiated(
        address indexed from,
        address indexed to,
        uint256 amount,
        bytes extraData
    );

    /**
     * @custom:legacy
     * @notice Emitted whenever a withdrawal of ETH from L2 to L1 is finalized.
     *
     * @param from      Address of the withdrawer.
     * @param to        Address of the recipient on L1.
     * @param amount    Amount of ETH withdrawn.
     * @param extraData Extra data attached to the withdrawal.
     */
    event ETHWithdrawalFinalized(
        address indexed from,
        address indexed to,
        uint256 amount,
        bytes extraData
    );

    /**
     * @custom:legacy
     * @notice Emitted whenever an ERC20 deposit is initiated.
     *
     * @param l1Token   Address of the token on L1.
     * @param l2Token   Address of the corresponding token on L2.
     * @param from      Address of the depositor.
     * @param to        Address of the recipient on L2.
     * @param amount    Amount of the ERC20 deposited.
     * @param extraData Extra data attached to the deposit.
     */
    event ERC20DepositInitiated(
        address indexed l1Token,
        address indexed l2Token,
        address indexed from,
        address to,
        uint256 amount,
        bytes extraData
    );

    /**
     * @custom:legacy
     * @notice Emitted whenever an ERC20 withdrawal is finalized.
     *
     * @param l1Token   Address of the token on L1.
     * @param l2Token   Address of the corresponding token on L2.
     * @param from      Address of the withdrawer.
     * @param to        Address of the recipient on L1.
     * @param amount    Amount of the ERC20 withdrawn.
     * @param extraData Extra data attached to the withdrawal.
     */
    event ERC20WithdrawalFinalized(
        address indexed l1Token,
        address indexed l2Token,
        address indexed from,
        address to,
        uint256 amount,
        bytes extraData
    );

    /**
     * @custom:semver 1.1.0
     *
     * @param _messenger Address of the L1CrossDomainMessenger.
     */
    constructor(address payable _messenger)
        Semver(1, 1, 0)
        StandardBridge(_messenger, payable(Predeploys.L2_STANDARD_BRIDGE))
    {}

    /**
     * @notice Allows EOAs to bridge ETH by sending directly to the bridge.
     */
    receive() external payable override onlyEOA {
        _initiateETHDeposit(msg.sender, msg.sender, RECEIVE_DEFAULT_GAS_LIMIT, bytes(""));
    }

    /**
     * @custom:legacy
     * @notice Deposits some amount of ETH into the sender's account on L2.
     *
     * @param _minGasLimit Minimum gas limit for the deposit message on L2.
     * @param _extraData   Optional data to forward to L2. Data supplied here will not be used to
     *                     execute any code on L2 and is only emitted as extra data for the
     *                     convenience of off-chain tooling.
     */
    function depositETH(uint32 _minGasLimit, bytes calldata _extraData) external payable onlyEOA {
        _initiateETHDeposit(msg.sender, msg.sender, _minGasLimit, _extraData);
    }

    /**
     * @custom:legacy
     * @notice Deposits some amount of ETH into a target account on L2.
     *         Note that if ETH is sent to a contract on L2 and the call fails, then that ETH will
     *         be locked in the L2StandardBridge. ETH may be recoverable if the call can be
     *         successfully replayed by increasing the amount of gas supplied to the call. If the
     *         call will fail for any amount of gas, then the ETH will be locked permanently.
     *
     * @param _to          Address of the recipient on L2.
     * @param _minGasLimit Minimum gas limit for the deposit message on L2.
     * @param _extraData   Optional data to forward to L2. Data supplied here will not be used to
     *                     execute any code on L2 and is only emitted as extra data for the
     *                     convenience of off-chain tooling.
     */
    function depositETHTo(
        address _to,
        uint32 _minGasLimit,
        bytes calldata _extraData
    ) external payable {
        _initiateETHDeposit(msg.sender, _to, _minGasLimit, _extraData);
    }

    /**
     * @custom:legacy
     * @notice Deposits some amount of ERC20 tokens into the sender's account on L2.
     *
     * @param _l1Token     Address of the L1 token being deposited.
     * @param _l2Token     Address of the corresponding token on L2.
     * @param _amount      Amount of the ERC20 to deposit.
     * @param _minGasLimit Minimum gas limit for the deposit message on L2.
     * @param _extraData   Optional data to forward to L2. Data supplied here will not be used to
     *                     execute any code on L2 and is only emitted as extra data for the
     *                     convenience of off-chain tooling.
     */
    function depositERC20(
        address _l1Token,
        address _l2Token,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    ) external virtual onlyEOA {
        _initiateERC20Deposit(
            _l1Token,
            _l2Token,
            msg.sender,
            msg.sender,
            _amount,
            _minGasLimit,
            _extraData
        );
    }

    /**
     * @custom:legacy
     * @notice Deposits some amount of ERC20 tokens into a target account on L2.
     *
     * @param _l1Token     Address of the L1 token being deposited.
     * @param _l2Token     Address of the corresponding token on L2.
     * @param _to          Address of the recipient on L2.
     * @param _amount      Amount of the ERC20 to deposit.
     * @param _minGasLimit Minimum gas limit for the deposit message on L2.
     * @param _extraData   Optional data to forward to L2. Data supplied here will not be used to
     *                     execute any code on L2 and is only emitted as extra data for the
     *                     convenience of off-chain tooling.
     */
    function depositERC20To(
        address _l1Token,
        address _l2Token,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    ) external virtual {
        _initiateERC20Deposit(
            _l1Token,
            _l2Token,
            msg.sender,
            _to,
            _amount,
            _minGasLimit,
            _extraData
        );
    }

    /**
     * @custom:legacy
     * @notice Finalizes a withdrawal of ETH from L2.
     *
     * @param _from      Address of the withdrawer on L2.
     * @param _to        Address of the recipient on L1.
     * @param _amount    Amount of ETH to withdraw.
     * @param _extraData Optional data forwarded from L2.
     */
    function finalizeETHWithdrawal(
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _extraData
    ) external payable {
        finalizeBridgeETH(_from, _to, _amount, _extraData);
    }

    /**
     * @custom:legacy
     * @notice Finalizes a withdrawal of ERC20 tokens from L2.
     *
     * @param _l1Token   Address of the token on L1.
     * @param _l2Token   Address of the corresponding token on L2.
     * @param _from      Address of the withdrawer on L2.
     * @param _to        Address of the recipient on L1.
     * @param _amount    Amount of the ERC20 to withdraw.
     * @param _extraData Optional data forwarded from L2.
     */
    function finalizeERC20Withdrawal(
        address _l1Token,
        address _l2Token,
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _extraData
    ) external {
        finalizeBridgeERC20(_l1Token, _l2Token, _from, _to, _amount, _extraData);
    }

    /**
     * @custom:legacy
     * @notice Retrieves the access of the corresponding L2 bridge contract.
     *
     * @return Address of the corresponding L2 bridge contract.
     */
    function l2TokenBridge() external view returns (address) {
        return address(OTHER_BRIDGE);
    }
    
    /**
     * @notice appends an array of valid version hashes to the chain through calldata, each VH is checked via the VH precompile.
     * the calldata should be contingious set of 32 byte version hashes to check via precompile. Will consume memory for 1 hash and check that the a hash value was parrtoed back to indicate validity.
     *
     */
    function appendSequencerBatch() external view {
        // Revert if the provided calldata does not consist of the 4 byte selector and segments of 32 bytes.
        require((msg.data.length - 4)%32 == 0);
        // Start reading calldata after the function selector.
        uint256 cursorPosition = 4;
        // Start loop. End once there is not sufficient remaining calldata to contain a 32 byte hash.
        while(cursorPosition <= (msg.data.length - 32)) {
            assembly{
                // Allocate memory for VH
                let memPtr := mload(0x40)
                // load 32 bytes from cursorPosition in calldata to memPtr location in memory
                calldatacopy(memPtr, cursorPosition, 0x20)
                // Set free pointer before function call.
                mstore(0x40, add(memPtr, 0x20))
                let result := staticcall(1500, 0x63, memPtr, 0x20, 0, 0)
                // check the RESULT does not indicate an error.
                switch result
                // Revert if precompile RESULT indicates an error.
                case 0 { revert(0, 0) }
                // Otherwise check the RETURNDATA
                default {
                    if eq(returndatasize(), 0) {
                        revert(0, 0)
                    }
                }
            }
            cursorPosition += 32;
        }
    }

    function appendSequencerBatchToL2() external {
        this.appendSequencerBatch();
        // Construct calldata
        bytes memory message = abi.encodeWithSelector(
            L2StandardBridge.appendSequencerBatch.selector,
            msg.data
        );
        // Send calldata into L2
        MESSENGER.sendMessage(this.l2TokenBridge(), message, RECEIVE_DEFAULT_GAS_LIMIT);
    }


    /**
     * @notice Internal function for initiating an ETH deposit.
     *
     * @param _from        Address of the sender on L1.
     * @param _to          Address of the recipient on L2.
     * @param _minGasLimit Minimum gas limit for the deposit message on L2.
     * @param _extraData   Optional data to forward to L2.
     */
    function _initiateETHDeposit(
        address _from,
        address _to,
        uint32 _minGasLimit,
        bytes memory _extraData
    ) internal {
        _initiateBridgeETH(_from, _to, msg.value, _minGasLimit, _extraData);
    }

    /**
     * @notice Internal function for initiating an ERC20 deposit.
     *
     * @param _l1Token     Address of the L1 token being deposited.
     * @param _l2Token     Address of the corresponding token on L2.
     * @param _from        Address of the sender on L1.
     * @param _to          Address of the recipient on L2.
     * @param _amount      Amount of the ERC20 to deposit.
     * @param _minGasLimit Minimum gas limit for the deposit message on L2.
     * @param _extraData   Optional data to forward to L2.
     */
    function _initiateERC20Deposit(
        address _l1Token,
        address _l2Token,
        address _from,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes memory _extraData
    ) internal {
        _initiateBridgeERC20(_l1Token, _l2Token, _from, _to, _amount, _minGasLimit, _extraData);
    }

    /**
     * @notice Emits the legacy ETHDepositInitiated event followed by the ETHBridgeInitiated event.
     *         This is necessary for backwards compatibility with the legacy bridge.
     *
     * @inheritdoc StandardBridge
     */
    function _emitETHBridgeInitiated(
        address _from,
        address _to,
        uint256 _amount,
        bytes memory _extraData
    ) internal override {
        emit ETHDepositInitiated(_from, _to, _amount, _extraData);
        super._emitETHBridgeInitiated(_from, _to, _amount, _extraData);
    }

    /**
     * @notice Emits the legacy ETHWithdrawalFinalized event followed by the ETHBridgeFinalized
     *         event. This is necessary for backwards compatibility with the legacy bridge.
     *
     * @inheritdoc StandardBridge
     */
    function _emitETHBridgeFinalized(
        address _from,
        address _to,
        uint256 _amount,
        bytes memory _extraData
    ) internal override {
        emit ETHWithdrawalFinalized(_from, _to, _amount, _extraData);
        super._emitETHBridgeFinalized(_from, _to, _amount, _extraData);
    }

    /**
     * @notice Emits the legacy ERC20DepositInitiated event followed by the ERC20BridgeInitiated
     *         event. This is necessary for backwards compatibility with the legacy bridge.
     *
     * @inheritdoc StandardBridge
     */
    function _emitERC20BridgeInitiated(
        address _localToken,
        address _remoteToken,
        address _from,
        address _to,
        uint256 _amount,
        bytes memory _extraData
    ) internal override {
        emit ERC20DepositInitiated(_localToken, _remoteToken, _from, _to, _amount, _extraData);
        super._emitERC20BridgeInitiated(_localToken, _remoteToken, _from, _to, _amount, _extraData);
    }

    /**
     * @notice Emits the legacy ERC20WithdrawalFinalized event followed by the ERC20BridgeFinalized
     *         event. This is necessary for backwards compatibility with the legacy bridge.
     *
     * @inheritdoc StandardBridge
     */
    function _emitERC20BridgeFinalized(
        address _localToken,
        address _remoteToken,
        address _from,
        address _to,
        uint256 _amount,
        bytes memory _extraData
    ) internal override {
        emit ERC20WithdrawalFinalized(_localToken, _remoteToken, _from, _to, _amount, _extraData);
        super._emitERC20BridgeFinalized(_localToken, _remoteToken, _from, _to, _amount, _extraData);
    }
}
