// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBEP20 {
  function transfer(address recipient, uint256 amount)
    external
    returns (bool);
}


library SafeBEP20 {
    using Address for address;

    function safeTransfer(IBEP20 token, address to, uint256 value) internal {
        callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }
    function callOptionalReturn(IBEP20 token, bytes memory data) private {
        require(address(token).isContract(), "SafeBEP20: call to non-contract");

        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, "SafeBEP20: low-level call failed");

        if (returndata.length > 0) {
            require(abi.decode(returndata, (bool)), "SafeBEP20: BEP20 operation did not succeed");
        }
    }
}


/**
 * @dev Collection of functions related to the address type
 */
library Address {
  function isContract(address account) internal view returns (bool) {
    // According to EIP-1052, 0x0 is the value returned for not-yet created accounts
    // and 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470 is returned
    // for accounts without code, i.e. `keccak256('')`
    bytes32 codehash;
    bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
    // solhint-disable-next-line no-inline-assembly
    assembly { codehash := extcodehash(account) }
    return (codehash != accountHash && codehash != 0x0);
  }
}

contract Multisig {
    using SafeBEP20 for IBEP20;

    event ProposalCreated (
        address indexed requestor,
        uint indexed proposalIndex,
        bytes indexed data
    );

    event FundTransferred(address indexed receiver, uint256 indexed amount);
    event ApproveProposal(address indexed owner, uint256 indexed txIndex);
    event ExecuteProposal(address indexed owner, uint256 indexed txIndex);
    event RevokeApproval(address indexed owner, uint256 indexed txIndex);

    enum ProposalType { 
        TRANSFER_TARGET_OWNERSHIP, 
        WITHDRAW_TOKEN_FROM_TARGET, 
        WITHDRAW_ETH_FROM_TARGET, 
        WITHDRAW_TOKENS_OF_TARGET, 
        TRANSFER_ETH_FROM_MULTISIG, 
        TRANSFER_TOKEN_FROM_MULTISIG, 
        REPLACE_MULTISIG_SIGNER,
        ADD_NEW_SIGNER,
        UPDATE_REQ_APPROVALS 
    }

    enum ProposalState{ PENDING, COMPLETED, REJECTED }

    address[] public signers;
    mapping(address => bool) public isSigner;
    uint256 public numApprovalsRequired;

    struct Proposal {
        address targetContract;
        address from;
        address to;
        bytes data;
        uint256 amount;
        ProposalType proposalType;
        ProposalState state;
        uint256 numApprovals;
        uint256 numRejections;
    }

    // mapping from tx index => owner => bool
    mapping(uint256 => mapping(address => bool)) public isApproved;
    mapping(uint256 => mapping(address => bool)) public isRejected;

    Proposal[] public proposals;

    modifier onlySigner() {
        _isSigner();
        _;
    }

    modifier isPending(uint256 _proposalIndex) {
        _isPending(_proposalIndex);
        _;
    }


    constructor(address[] memory _signers, uint256 _numApprovalsRequired) {
        require(_signers.length > 0, "Signers Required");
        require(
            _numApprovalsRequired > 0 &&
                _numApprovalsRequired <= _signers.length,
            "Approvals Required Too Few"
        );

        for (uint256 i = 0; i < _signers.length; i++) {
            address signer = _signers[i];

            require(signer != address(0), "Invalid Signer Address");
            require(!isSigner[signer], "Signer Not Unique");

            isSigner[signer] = true;
            signers.push(signer);
        }

        numApprovalsRequired = _numApprovalsRequired;
    }


    /**
        * @dev receives ethereum
    */
    receive() external payable {}


    /**
        *@dev shows total number of proposals
     */
    function proposalCount() public view returns (uint256) {
        return proposals.length;
    }

    /**
    *@dev gets the detail of a proposal
    *@param _proposalIndex the index of the proposal of interest
     */
    function getProposal(uint256 _proposalIndex) public view returns (address targetContract, address from, address to, bytes memory data, uint256 amount, ProposalType _type, ProposalState _state, uint256 _approvals, uint256 _rejections) {
        Proposal memory proposal = proposals[_proposalIndex];

        return(proposal.targetContract, proposal.from, proposal.to, proposal.data, proposal.amount, proposal.proposalType, proposal.state, proposal.numApprovals, proposal.numRejections);
    }

    /**
        *@dev shows all the signers of this Multisig contract
     */
    function getSigners() public view returns (address[] memory) {
        return signers;
    }

    /**
        * @dev Creates a proposal to be executed on the target contract
        * @param _targetContract the target contract where the proposal will be executed
        * @param _from a previous value
        * @param _to a new value
        * @param _data bytes of the function signature with params to be executed on the target contract
        * @param _amount could be BNB amount, token amount or index of signer depends on which proposal implements it
        * @param _proposalType enumerable of proposal types
    */
    function _submitProposal(
        address _targetContract,
        address _from,
        address _to,
        bytes memory _data,
        uint256 _amount,
        ProposalType _proposalType
    ) private {
        address sender = msg.sender;
        uint proposalIndex = proposals.length;
        proposals.push(
            Proposal({
                targetContract: _targetContract,
                from: _from,
                to: _to,
                data: _data,
                amount: _amount,
                proposalType: _proposalType,
                state: ProposalState.PENDING,
                numApprovals: 1,
                numRejections: 0
            })
        );
        isApproved[proposalIndex][sender] = true;

        emit ProposalCreated(sender, proposalIndex, _data);
    }

    /**
     * @dev creates proposal to transfer ownership of target contract to a new owner
     * @param _targetContract the target contract whose ownership is to be transferred
     * @param _newOwner the proposed new owner of the target contract
    */
    function requestTransferOwnership(address _targetContract, address payable _newOwner) public onlySigner {
        _submitProposal(
            _targetContract,
            address(0),
            address(0),
            abi.encodeWithSignature("transferOwnership(address)", _newOwner),
            0,
            ProposalType.TRANSFER_TARGET_OWNERSHIP
        );
    }

    /**
     * @dev creates a proposal requesting the withdrawal of tokens of specific address from the target contract
     * @param _targetContract the target contract
     * @param _tokenAddress the address of the token to be withdrawn
    */
    function requestTokenWithdrawalOnTarget(address _targetContract, address _tokenAddress) public onlySigner {
        _submitProposal(
            _targetContract,
            address(0),
            address(0),
            abi.encodeWithSignature("withdraw(address)", _tokenAddress),
            0,
            ProposalType.WITHDRAW_TOKEN_FROM_TARGET
        );
    }

    /**
     * @dev creates a proposal requesting the withdrawal of fund BNB from the target contract
     * @param _targetContract the target contract
    */
    function requestETHWithdraw(address _targetContract) public onlySigner {
        _submitProposal(
            _targetContract,
            address(0),
            address(0),
            abi.encodeWithSignature("withdraw()"),
            0,
            ProposalType.WITHDRAW_ETH_FROM_TARGET
        );
    }

    /**
     * @dev creates a proposal requesting the withdrawal tokens minted by the contract which have been sent back into it
     * @param _targetContract the target contract
    */
    function requestTokenOfTargetWithdrawal(address _targetContract) external onlySigner {
        _submitProposal(
            _targetContract,
            address(0),
            address(0),
            abi.encodeWithSignature("withdrawTokens()"),
            0,
            ProposalType.WITHDRAW_TOKENS_OF_TARGET
        );
    }


    /**
     * @dev creates a proposal requesting the withdrawal tokens minted by the contract which have been sent back into it
     * @param _newSigner the new signer's address
    */
    function requestAddNewSigner(address _newSigner) external onlySigner {
        _submitProposal(
            address(this),
            address(0),
            _newSigner,
            "0x0",
            0,
            ProposalType.ADD_NEW_SIGNER
        );
    }


    /**
     * @dev creates a proposal requesting the withdrawal tokens minted by the contract which have been sent back into it
     * @param _numReqApproval the new amount of required approvals
    */
    function requestUpdateReqApprovals(uint256 _numReqApproval) external onlySigner {
        _submitProposal(
            address(this),
            address(0),
            address(0),
            "0x0",
            _numReqApproval,
            ProposalType.UPDATE_REQ_APPROVALS
        );
    }
    

    /**
        * @dev creates a proposal to send native token (ETH/BNB) from this Multisig to a receiver
        * @param _to receiver address
        * @param _amount the amount of BNB to be transferred
    */
    function requestTransferETH(address _to, uint256 _amount) public onlySigner {
        _submitProposal(
            address(this),
            address(0),
            _to,
            "0x0",
            _amount,
            ProposalType.TRANSFER_ETH_FROM_MULTISIG
        );
    }

    /**
        * @dev creates a proposal to ssend tokens from this Multisig to an address
        * @param _tokenAddress the token address of the token to be transferred
        * @param _to the address where the token is to be received
        * @param _amount the amount of token to be transferred
    */
    function requestTokenTransfer(address _tokenAddress, address _to, uint256 _amount) public onlySigner {
        _submitProposal(
            _tokenAddress,
            address(0),
            _to,
            "0x0",
            _amount,
            ProposalType.TRANSFER_TOKEN_FROM_MULTISIG
        );
    }

    /**
        * @dev creates a proposal to replace an existing signer with another one. This may be useful when a signer lost his key or becomes unavailable
        * @param _prevSigner the siiner's address to be replaced
        * @param _newSigner the proposed new signer's address
        * @param _signerIndex the index of the signer in Multisig's signers array
    */
    function requestReplaceSigner(address _prevSigner, address _newSigner, uint256 _signerIndex) public onlySigner {
        require(signers[_signerIndex] == _prevSigner, "Incorrect Signer Index");
        require(_newSigner != address(0), "Invalid Signer");
        _submitProposal(
            address(this),
            _prevSigner,
            _newSigner,
            "0x0",
            _signerIndex,
            ProposalType.REPLACE_MULTISIG_SIGNER
        );
    }

    /**
        * @dev executes a proposal on the target contract after the required signers have approved it
        * @param _proposalIndex the index of the proposal to be executed
    */
    function executeRemoteProposal(uint256 _proposalIndex) public isPending(_proposalIndex) {
        Proposal storage proposal = proposals[_proposalIndex];
        require(
            proposal.numApprovals >= numApprovalsRequired,
           "Needs More Approvals"
        );
        proposal.state = ProposalState.COMPLETED;
        // solhint-disable-next-line avoid-low-level-calls
        (bool success,) = proposal.targetContract.call{value: 0}(proposal.data);
        require(success, "Proposal Execution Failed");

        emit ExecuteProposal(msg.sender, _proposalIndex);
    }


    function executeMultisigProposal(uint256 _proposalIndex) public isPending(_proposalIndex) {
        Proposal storage proposal = proposals[_proposalIndex];
        require(
            proposal.numApprovals >= numApprovalsRequired,
           "Insufficient Approvals"
        );

        if(proposal.proposalType == ProposalType.TRANSFER_ETH_FROM_MULTISIG) {
            proposal.state = ProposalState.COMPLETED;
            _executeTransferETH(proposal.to, proposal.amount);
        } else if(proposal.proposalType == ProposalType.TRANSFER_TOKEN_FROM_MULTISIG) {
            proposal.state = ProposalState.COMPLETED;
            _executeTokenTransfer(proposal.targetContract, proposal.to, proposal.amount);
        } else if(proposal.proposalType == ProposalType.REPLACE_MULTISIG_SIGNER) {
            proposal.state = ProposalState.COMPLETED;
            _executeReplaceSigner(proposal.from, proposal.to, proposal.amount);
        } else if(proposal.proposalType == ProposalType.ADD_NEW_SIGNER) {
            proposal.state = ProposalState.COMPLETED;
            _executeAddNewSigner(proposal.to);
        } else if(proposal.proposalType == ProposalType.UPDATE_REQ_APPROVALS) {
            proposal.state = ProposalState.COMPLETED;
            _executeUpdateReqApprovals(proposal.amount);
        }

        require(proposal.state == ProposalState.COMPLETED, "Incorrect Proposal");
        emit ExecuteProposal(msg.sender, _proposalIndex);
    }

    /**
        * @dev executes tranfer of native token (ETH/BNB) proposal
        * @param _to receiver address
        * @param _amount amount of ETH/BNB to be transferred
    */
    function _executeTransferETH(address _to, uint256 _amount) internal {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = payable(_to).call{value: _amount}("");
        require(success, "Transfer Failed");
    }


    /**
        * @dev executes tranfer of erc2-/bep20 token
        * @param _token address of token that will be transferred
        * @param _receiver the desticnation of the tokens being withdrawn
        * @param _amount amount of tokens to be transferred
    */
    function _executeTokenTransfer(address _token, address _receiver, uint256 _amount) internal {
        IBEP20(_token).safeTransfer(_receiver, _amount);
    }

    /**
        * @dev executes tranfer of erc2-/bep20 token
        * @param _from oldSigner
        * @param _to newSigner
        * @param _signerIndex index of signer in the signers array
    */
    function _executeReplaceSigner(address _from, address _to, uint256 _signerIndex) internal {
        isSigner[_from] = false;
        signers[_signerIndex] = _to;
        isSigner[_to] = true;
    }

    /**
        * @dev adds new siger to the multisig contract
        * @param _newSigner index of signer in the signers array
    */
    function _executeAddNewSigner(address _newSigner) internal {
        require(_newSigner != address(0), "Invalid Signer Address");
        require(!isSigner[_newSigner], "Already A Signer");
        signers.push(_newSigner);
        isSigner[_newSigner] = true;
    }

    /**
        * @dev adds new siger to the multisig contract
        * @param _num new number of required signers
    */
    function _executeUpdateReqApprovals(uint256 _num) internal {
        require(
            _num > 0 &&
                _num <= signers.length,
            "Too Few Approvals Required"
        );
        numApprovalsRequired = _num;
    }

    /**
        * @dev Let's a signer approve a specific proposal
        * @param _proposalIndex the index of the proposal to be approved
    */
    function approveProposal(uint256 _proposalIndex) public isPending(_proposalIndex) {
        address sender = msg.sender;
        require(!isApproved[_proposalIndex][sender], "Already Approved");
        Proposal storage proposal = proposals[_proposalIndex];
        proposal.numApprovals += 1;
        isApproved[_proposalIndex][sender] = true;
        emit ApproveProposal(sender, _proposalIndex);
    }

    /**
        * @dev Let's a signer reject a specific proposal
        * @param _proposalIndex the index of the proposal to be rejected
    */
    function rejectProposal(uint256 _proposalIndex) public isPending(_proposalIndex) {
        address sender = msg.sender;
        bool _wasRejected = isRejected[_proposalIndex][sender];
        require(!isApproved[_proposalIndex][sender], "Revoke Approval First");
        require(!_wasRejected, "Already Rejected");
        Proposal storage proposal = proposals[_proposalIndex];
        proposal.numRejections += 1;
        isRejected[_proposalIndex][sender] = true;
        if(proposal.numRejections == numApprovalsRequired) {
            proposal.state = ProposalState.REJECTED;
        }
        emit ApproveProposal(sender, _proposalIndex);
    }

    /**
        * @dev Let's a signer revoke their approval after previously approving it
        * @param _proposalIndex the index of the proposal to be executed
    */
    function revokeApproval(uint256 _proposalIndex) public isPending(_proposalIndex) {
        address sender = msg.sender;
        Proposal storage proposal = proposals[_proposalIndex];
        require(isApproved[_proposalIndex][sender], "Proposal Wasn't Approved");
        proposal.numApprovals -= 1;
        isApproved[_proposalIndex][sender] = false;
        emit RevokeApproval(sender, _proposalIndex);
    }


    /**
        * @dev checks for signer signature, if proposal is valid and is pending execution
        * @param _proposalIndex index of proposal
    */
    function _isPending(uint256 _proposalIndex) private view {
        _isSigner();
        require(_proposalIndex < proposals.length, "Invalid Proposal");
        require(proposals[_proposalIndex].state == ProposalState.PENDING, "Inactive Proposal");
    }

    /**
        * @dev checks to see if caller is a signer
    */
    function _isSigner() private view {
        require(isSigner[msg.sender], "Not A Signer");
    }
}
