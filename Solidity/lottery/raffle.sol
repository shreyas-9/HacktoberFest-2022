//Raffle contract
//enter the lottery (amount to be paid)
//select a random winner(must be verified)
//Chainlink Oracle ->Randomness ,Automated execution of smart contract

//SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";
import "hardhat/console.sol";

error Raffle_NotEnoughETHentered();
error Raffle_TransferFailed();
error Raffle__NotOpen();
error Raffle__UpkeepNotNeeded(uint256 currentBalance,uint256 numPlayers,uint256 raffleState);

/** @title A Raffle Contract
 * @author duplixx
 * @notice This contract is for creating untamperable decentralized smart contract 
 */


abstract contract Raffle is VRFConsumerBaseV2, KeeperCompatibleInterface {
  enum RaffleState {
    OPEN,
    CALCULATING
  }
  //uint256 0=OPEN, 1=CALCULATING
  /*State variables*/
  VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
  uint256 private immutable i_entranceFee;
  bytes32 private immutable i_gasLane;
  uint64 private immutable i_subscriptionId;
  uint32 private immutable i_callbackGasLimit;
  uint16 private constant REQUEST_CONFIRMATIONS = 3;
  uint32 private constant NUM_WORDS = 1;

  /*Lottery variables*/
  address private s_recentWinner;
  address payable[] private s_players;
  RaffleState private s_raffleState;
  uint256 private s_lastTimeStamp;
  uint256 private immutable i_interval;

  event RaffleEnter(address indexed players);
  event RequestedRaffleWinner(uint256 indexed requestId);
  event WinnerPicked(address indexed winner);

  /*Functions*/
  constructor(
    address vrfCoordinatorV2,
    uint256 entranceFee,
    bytes32 gasLane,
    uint64 subscriptionId,
    uint32 callbackGasLimit,
    uint256 interval
  ) VRFConsumerBaseV2(vrfCoordinatorV2) {
    i_entranceFee = entranceFee;
    i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinatorV2);
    i_gasLane = gasLane;
    i_subscriptionId = subscriptionId;
    i_callbackGasLimit = callbackGasLimit;
    s_raffleState = RaffleState.OPEN;
    s_lastTimeStamp = block.timestamp;
    i_interval = interval;
  }

  function enterRaffle() public payable {
    // require(msg.value>i_entranceFee,"Not enough ETH!"); //we are not using this cuz its not gas efficient
    if (msg.value < i_entranceFee) {
      revert Raffle_NotEnoughETHentered();
    }
    if (s_raffleState != RaffleState.OPEN) {
      revert Raffle__NotOpen();
    }
    s_players.push(payable(msg.sender));
    emit RaffleEnter(msg.sender);
  }

  function getEntranceFee() public view returns (uint256) {
    return i_entranceFee;
  }

  function checkUpkeep(
    bytes calldata /*checkData*/
  ) public override returns (bool upKeepNeeded, bytes memory) {
    bool isOpen = (RaffleState.OPEN == s_raffleState);
    //block.timestamp - last block timestamp
    bool timePassed = ((block.timestamp - s_lastTimeStamp) > i_interval);
    bool hasPlayers = (s_players.length > 0);
    bool hasBalance = address(this).balance > 0;
    upKeepNeeded = (isOpen && timePassed && hasPlayers && hasBalance);
  }

  function performUpkeep(
    bytes calldata /*performData*/
  ) external override {
    (bool upKeepNeeded, ) = checkUpkeep("");
    if (!upKeepNeeded) {
      revert Raffle__UpkeepNotNeeded(
        address(this).balance,
        s_players.length,
        uint256(s_raffleState)
      );
    }
    s_raffleState = RaffleState.CALCULATING;
    uint256 requestId = i_vrfCoordinator.requestRandomWords(
      i_gasLane,
      i_subscriptionId,
      REQUEST_CONFIRMATIONS,
      i_callbackGasLimit,
      NUM_WORDS
    );
    emit RequestedRaffleWinner(requestId);
  }

  function fullfillRandomWords(
    uint256, /*requestId*/
    uint256[] memory randomWords
  ) internal {
    uint256 indexOfwinner = randomWords[0] % s_players.length;
    address payable recentWinner = s_players[indexOfwinner];
    s_recentWinner = recentWinner;
    s_raffleState = RaffleState.OPEN;
    s_players = new address payable[](0);
    s_lastTimeStamp = block.timestamp;
    (bool success, ) = recentWinner.call{value: address(this).balance}("");
    if (!success) {
      revert Raffle_TransferFailed();
    }
    emit WinnerPicked(recentWinner);
  }

  function getPlayers(uint256 index) public view returns (address) {
    return s_players[index];
  }

  function getRecentWinner(uint256 index) public view returns (address) {
    return s_recentWinner;
  }
  function getRaffleState() public view returns (RaffleState) {
    return s_raffleState;
  }
  function getNumWords() public view returns (uint256){
      return NUM_WORDS;
  }
}
