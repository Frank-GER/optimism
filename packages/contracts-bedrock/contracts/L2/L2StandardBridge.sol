// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Predeploys } from "../libraries/Predeploys.sol";
import { StandardBridge } from "../universal/StandardBridge.sol";
import { Semver } from "../universal/Semver.sol";
import { OptimismMintableERC20 } from "../universal/OptimismMintableERC20.sol";

/**
 * @custom:proxied
 * @custom:predeploy 0x4200000000000000000000000000000000000010
 * @title L2StandardBridge
 * @notice The L2StandardBridge is responsible for transfering ETH and ERC20 tokens between L1 and
 *         L2. In the case that an ERC20 token is native to L2, it will be escrowed within this
 *         contract. If the ERC20 token is native to L1, it will be burnt.
 *         NOTE: this contract is not intended to support all variations of ERC20 tokens. Examples
 *         of some token types that may not be properly supported by this contract include, but are
 *         not limited to: tokens with transfer fees, rebasing tokens, and tokens with blocklists.
 */
contract L2StandardBridge is StandardBridge, Semver {

    mapping(bytes32 => bool) public podaMap;

    /**
     * @custom:legacy
     * @notice Emitted whenever a withdrawal from L2 to L1 is initiated.
     *
     * @param l1Token   Address of the token on L1.
     * @param l2Token   Address of the corresponding token on L2.
     * @param from      Address of the withdrawer.
     * @param to        Address of the recipient on L1.
     * @param amount    Amount of the ERC20 withdrawn.
     * @param extraData Extra data attached to the withdrawal.
     */
    event WithdrawalInitiated(
        address indexed l1Token,
        address indexed l2Token,
        address indexed from,
        address to,
        uint256 amount,
        bytes extraData
    );

    /**
     * @custom:legacy
     * @notice Emitted whenever an ERC20 deposit is finalized.
     *
     * @param l1Token   Address of the token on L1.
     * @param l2Token   Address of the corresponding token on L2.
     * @param from      Address of the depositor.
     * @param to        Address of the recipient on L2.
     * @param amount    Amount of the ERC20 deposited.
     * @param extraData Extra data attached to the deposit.
     */
    event DepositFinalized(
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
     * @param _otherBridge Address of the L1StandardBridge.
     */
    constructor(address payable _otherBridge)
        Semver(1, 1, 0)
        StandardBridge(payable(Predeploys.L2_CROSS_DOMAIN_MESSENGER), _otherBridge)
    {}

    /**
     * @notice Allows EOAs to bridge ETH by sending directly to the bridge.
     */
    receive() external payable override onlyEOA {
        _initiateWithdrawal(
            Predeploys.LEGACY_ERC20_ETH,
            msg.sender,
            msg.sender,
            msg.value,
            RECEIVE_DEFAULT_GAS_LIMIT,
            bytes("")
        );
    }

    /**
     * @custom:legacy
     * @notice Initiates a withdrawal from L2 to L1.
     *         This function only works with OptimismMintableERC20 tokens or ether. Use the
     *         `bridgeERC20` function to bridge native L2 tokens to L1.
     *
     * @param _l2Token     Address of the L2 token to withdraw.
     * @param _amount      Amount of the L2 token to withdraw.
     * @param _minGasLimit Minimum gas limit to use for the transaction.
     * @param _extraData   Extra data attached to the withdrawal.
     */
    function withdraw(
        address _l2Token,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    ) external payable virtual onlyEOA {
        _initiateWithdrawal(_l2Token, msg.sender, msg.sender, _amount, _minGasLimit, _extraData);
    }

    /**
     * @custom:legacy
     * @notice Initiates a withdrawal from L2 to L1 to a target account on L1.
     *         Note that if ETH is sent to a contract on L1 and the call fails, then that ETH will
     *         be locked in the L1StandardBridge. ETH may be recoverable if the call can be
     *         successfully replayed by increasing the amount of gas supplied to the call. If the
     *         call will fail for any amount of gas, then the ETH will be locked permanently.
     *         This function only works with OptimismMintableERC20 tokens or ether. Use the
     *         `bridgeERC20To` function to bridge native L2 tokens to L1.
     *
     * @param _l2Token     Address of the L2 token to withdraw.
     * @param _to          Recipient account on L1.
     * @param _amount      Amount of the L2 token to withdraw.
     * @param _minGasLimit Minimum gas limit to use for the transaction.
     * @param _extraData   Extra data attached to the withdrawal.
     */
    function withdrawTo(
        address _l2Token,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    ) external payable virtual {
        _initiateWithdrawal(_l2Token, msg.sender, _to, _amount, _minGasLimit, _extraData);
    }

    /**
     * @custom:legacy
     * @notice Finalizes a deposit from L1 to L2. To finalize a deposit of ether, use address(0)
     *         and the l1Token and the Legacy ERC20 ether predeploy address as the l2Token.
     *
     * @param _l1Token   Address of the L1 token to deposit.
     * @param _l2Token   Address of the corresponding L2 token.
     * @param _from      Address of the depositor.
     * @param _to        Address of the recipient.
     * @param _amount    Amount of the tokens being deposited.
     * @param _extraData Extra data attached to the deposit.
     */
    function finalizeDeposit(
        address _l1Token,
        address _l2Token,
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _extraData
    ) external payable virtual {
        if (_l1Token == address(0) && _l2Token == Predeploys.LEGACY_ERC20_ETH) {
            finalizeBridgeETH(_from, _to, _amount, _extraData);
        } else {
            finalizeBridgeERC20(_l2Token, _l1Token, _from, _to, _amount, _extraData);
        }
    }

    /**
     * @custom:legacy
     * @notice Retrieves the access of the corresponding L1 bridge contract.
     *
     * @return Address of the corresponding L1 bridge contract.
     */
    function l1TokenBridge() external view returns (address) {
        return address(OTHER_BRIDGE);
    }

    /**
     * @custom:legacy
     * @notice Internal function to a withdrawal from L2 to L1 to a target account on L1.
     *
     * @param _l2Token     Address of the L2 token to withdraw.
     * @param _from        Address of the withdrawer.
     * @param _to          Recipient account on L1.
     * @param _amount      Amount of the L2 token to withdraw.
     * @param _minGasLimit Minimum gas limit to use for the transaction.
     * @param _extraData   Extra data attached to the withdrawal.
     */
    function _initiateWithdrawal(
        address _l2Token,
        address _from,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes memory _extraData
    ) internal {
        if (_l2Token == Predeploys.LEGACY_ERC20_ETH) {
            _initiateBridgeETH(_from, _to, _amount, _minGasLimit, _extraData);
        } else {
            address l1Token = OptimismMintableERC20(_l2Token).l1Token();
            _initiateBridgeERC20(_l2Token, l1Token, _from, _to, _amount, _minGasLimit, _extraData);
        }
    }

    /**
     * @notice appends an array of valid version hashes to the chain through calldata, each VH is checked via the VH precompile.
     * the calldata should be contingious set of 32 byte version hashes to check via precompile. Will consume memory for 1 hash and check that the a hash value was parrtoed back to indicate validity.
     *
     */
    function appendSequencerBatch() external onlyOtherBridge {
        // Revert if the provided calldata does not consist of the 4 byte selector and segments of 32 bytes.
        require((msg.data.length - 4)%32 == 0);
        // Start reading calldata after the function selector.
        uint256 cursorPosition = 4;
        // Start loop. End once there is not sufficient remaining calldata to contain a 32 byte hash.
        while(cursorPosition <= (msg.data.length - 32)) {
            podaMap[bytes32(msg.data[cursorPosition])] = true;
            cursorPosition += 32;
        }
    }

    /**
     * @notice Emits the legacy WithdrawalInitiated event followed by the ETHBridgeInitiated event.
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
        emit WithdrawalInitiated(
            address(0),
            Predeploys.LEGACY_ERC20_ETH,
            _from,
            _to,
            _amount,
            _extraData
        );
        super._emitETHBridgeInitiated(_from, _to, _amount, _extraData);
    }

    /**
     * @notice Emits the legacy DepositFinalized event followed by the ETHBridgeFinalized event.
     *         This is necessary for backwards compatibility with the legacy bridge.
     *
     * @inheritdoc StandardBridge
     */
    function _emitETHBridgeFinalized(
        address _from,
        address _to,
        uint256 _amount,
        bytes memory _extraData
    ) internal override {
        emit DepositFinalized(
            address(0),
            Predeploys.LEGACY_ERC20_ETH,
            _from,
            _to,
            _amount,
            _extraData
        );
        super._emitETHBridgeFinalized(_from, _to, _amount, _extraData);
    }

    /**
     * @notice Emits the legacy WithdrawalInitiated event followed by the ERC20BridgeInitiated
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
        emit WithdrawalInitiated(_remoteToken, _localToken, _from, _to, _amount, _extraData);
        super._emitERC20BridgeInitiated(_localToken, _remoteToken, _from, _to, _amount, _extraData);
    }

    /**
     * @notice Emits the legacy DepositFinalized event followed by the ERC20BridgeFinalized event.
     *         This is necessary for backwards compatibility with the legacy bridge.
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
        emit DepositFinalized(_remoteToken, _localToken, _from, _to, _amount, _extraData);
        super._emitERC20BridgeFinalized(_localToken, _remoteToken, _from, _to, _amount, _extraData);
    }
}
