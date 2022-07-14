// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";

interface IAlToken is IERC20 {
    function refreshBalance(address account) external;
    function refreshTotalSupply() external returns(uint256);
    function decimals() external view returns(uint8);
    function rewardSupply() external view returns(uint256);
}

contract AlNft is ERC1155Upgradeable, OwnableUpgradeable {
    struct Tier {
        uint256 mintPrice;
        uint256 rewardPerSec;
        uint256 count;
        uint256 totalExcuded;
    }
    struct Pending {
      uint256 count;
      uint256 endTime;
    }
    // base uri
    uint8 LAST_ID;
    string private _name;
    string private _symbol;
    mapping(uint8 => Tier) public tiers;
    mapping(address => uint256) public lastRwTime;
    IAlToken public alToken;
    uint256 public rewardStopTime;
    bool public pause;
    mapping(address => mapping(uint8 => Pending)) public pendings;
    uint256 lastClaimedTime;
    uint256 pendingDuration;

    function initialize(string memory uri_, address alToken_)
        public
        initializer
    {
        __Ownable_init();
        __ERC1155_init(uri_);
        init(alToken_);
    }

    function init(address alToken_) private {
      _name = "Alien NFT";
      _symbol = "ALNFT";
      alToken = IAlToken(alToken_);
      uint8 decimal = alToken.decimals();
      uint256 oneEther = 10**decimal;
      tiers[1].mintPrice = 1 ether;
      tiers[1].rewardPerSec = (oneEther*86400) / 86400; // 100 ether per day 
      tiers[2].mintPrice = 0.001 ether;
      tiers[2].rewardPerSec = (oneEther*100) / 86400;
      tiers[3].mintPrice = 0.001 ether;
      tiers[3].rewardPerSec = (oneEther*100) / 86400;
      tiers[4].mintPrice = 0.001 ether;
      tiers[4].rewardPerSec = (oneEther*100) / 86400;
      tiers[5].mintPrice = 0.001 ether;
      tiers[5].rewardPerSec = (oneEther*100) / 86400;
      tiers[6].mintPrice = 0.001 ether;
      tiers[6].rewardPerSec = (oneEther*100) / 86400;
      LAST_ID = 6;
      uint256 MAX_INT = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
      rewardStopTime = MAX_INT;
      pendingDuration = 60;
    }

    function setTier(uint8 id, uint256 mintPrice, uint256 dailyReward) public onlyOwner {
      tiers[id].mintPrice = mintPrice;
      tiers[id].rewardPerSec = dailyReward/86400;
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function setAlToken(address addr) public onlyOwner {
        alToken = IAlToken(addr);
    }

    // set uri
    function setBaseURI(string memory baseURI_) public onlyOwner {
        _setURI(baseURI_);
    }

    function setMintAllowance(bool flag) public onlyOwner {
      pause = flag;
    }

    function setPendingDuration(uint256 duration) public onlyOwner {
      pendingDuration = duration;
    }

    // total claimable nfts
    function totalClaimableNft() public view returns(uint256) {
      uint256 totalCount = 0;
      for(uint8 i = 1; i <= LAST_ID; i ++) {
        totalCount += tiers[i].count;
      }

      return totalCount;
    }

    // total exclueded amount of rewards
    function totalExcludedRewardAmount() public view returns(uint256) {
      uint256 total = 0;
      for(uint8 i = 1; i <= LAST_ID; i ++) {
        total += tiers[i].totalExcuded;
      }
      return total;
    }

    function mint(uint8 id) public /* payable */
    {
      require(pause == false, "[ALNFT] Temporarily paused to mint!");
      require(tiers[id].mintPrice != 0, "[ALNFT] Unknown NFT id!");
      // require (msg.value >= tiers[id].mintPrice, "[ALNFT] Pay amount less then the mint price!");
      alToken.transferFrom(msg.sender, address(this), tiers[id].mintPrice);
      _mint(msg.sender, id, 1, "0x00");
    }

    function claimTotalTiersRewards() public {
      uint256 total = alToken.refreshTotalSupply();
      for(uint8 i = 1; i <= LAST_ID; i ++) {
        lastClaimedTime = _btm();
      }
      if (total > alToken.rewardSupply() && rewardStopTime == 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff)
        rewardStopTime = block.timestamp;
    }

    function clearPending(address account) private {
      for(uint8 i = 1; i < LAST_ID; i ++) {
        Pending storage p = pendings[account][i];
        if (block.timestamp > p.endTime)
        {
          p.endTime = 0;
          p.count = 0;
        }
      }
    }

    function claimRewards(address account) public {
      clearPending(account);
      alToken.refreshBalance(account);
      lastRwTime[account] = _btm();
    }

    function _btm() private view returns(uint256) {
      return block.timestamp < rewardStopTime ? block.timestamp : rewardStopTime;
    }

    function rewardsOfTier(uint8 id) public view returns(uint256) {
      if (lastClaimedTime == 0)
        return 0;
      return tiers[id].count 
        * (_btm() - lastClaimedTime) 
        * tiers[id].rewardPerSec;
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal override {
        if (address(alToken) == address(0)) return;
        claimTotalTiersRewards();
        if (from != address(0))
          claimRewards(from);
        
        if (to != address(0))  {
          claimRewards(to);
        }

        for(uint i = 0; i < ids.length; i ++) {
          uint8 id = uint8(ids[i]);
          if (from == address(0)) // minting
            tiers[id].count ++;
          if (to != address(0)) {
            if (pendings[to][id].endTime == 0) {
              pendings[to][id].endTime = block.timestamp + pendingDuration;
              tiers[id].totalExcuded += pendingDuration*tiers[id].rewardPerSec;
            }
            pendings[to][id].count ++;
          }
        }
    }

    function totalRewards() public view returns(uint256) {
      uint256 tRewards = 0;
      for(uint8 i = 1; i <= LAST_ID; i ++) {
        tRewards += rewardsOfTier(i);
      }

      return tRewards;
    }

    function withdrawFunds() public onlyOwner {
        uint256 amount = address(this).balance;
        (bool sent, ) = payable(msg.sender).call{value: amount, gas: 30000}("");
        require(sent, "Failed to withdraw!");
    }

    function rewardBalance(address account) public view returns (uint256) {
      if (lastRwTime[account] == 0) return 0;
      uint256 _totalRewards = 0;
      for (uint8 i = 1; i <= LAST_ID; i++) {
        uint256 rCount = balanceOf(account, i);
        uint256 pCount = pendings[account][i].count;
        rCount -= pCount;
        uint256 rAmount = rCount * tiers[i].rewardPerSec * (_btm() - lastRwTime[account]);
        uint256 pAmount = 0;
        if (_btm() > pendings[account][i].endTime) {
          pAmount = pCount*tiers[i].rewardPerSec*(_btm()-pendings[account][i].endTime);
        }
        uint256 reward = rAmount + pAmount;

        _totalRewards += reward;
      }

      return _totalRewards;
    }

    receive() external payable {}
}
