pragma solidity ^0.8.15;
//SPDX-License-Identifier: UNLICENSED
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

interface IAlNft is IERC1155 {
    function rewardBalance(address account) external view returns (uint256);
    function claimRewards(address account) external;
    function totalRewards() external view returns(uint256);
    function claimTotalTiersRewards() external;
    function totalExcludedRewardAmount() external view returns(uint256);
}

contract AlToken is OwnableUpgradeable, IERC20Upgradeable {
    string private _name;
    string private _symbol;
    uint8 private _decimals;
    uint256 public _totalSupply;
    uint256 private _maxSupply;
    uint256 public rewardSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    IAlNft public alNft;
    IUniswapV2Router02 public router;
    address public pair;
    mapping (address => bool) public _isExcludedFromFee;
    mapping(address => bool) public blacklist;
    bool inSwap;
    // fees
    uint256 private _totalBuyFee;
    uint256 private _totalSellFee;
    uint256 private _feeRate;
    // fee distribution wallets
    address private _walletA;
    address private _walletB;
    address private _walletC;
    address private _burnWallet;
    // liquidity
    uint256 private numTokensToAddToLiquidity;

    modifier swapping() {
        inSwap = true;
        _;
        inSwap = false;
    }

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );
    event AutoLP(bool flag);
    event Received(address, uint256);

    function init() public onlyOwner {
        setupLP();
        _totalBuyFee = 600;     // buy fee  : 6%
        _totalSellFee = 1500;   // sell fee : 15%
        _feeRate = 10000;
        numTokensToAddToLiquidity = 1 ether;

        _walletA = 0x3244585147151AaAe3B05bc71D6217150F61f349;
        _walletB = 0x15C6A26A9A24d856DB42F7baDC2c4FD68096e61F;
        _walletC = 0xbEF53b386767DD99D785cb949709EA2c6C3e745b;
        _burnWallet = 0x000000000000000000000000000000000000dEaD;
    }

    function initialize(
        string memory n_,
        string memory s_,
        uint8 d_
    ) public initializer {
        __Ownable_init();
        _name = n_;
        _symbol = s_;
        _decimals = d_;
        uint256 oneMillion = (10**_decimals) * (10**7);
        _totalSupply = oneMillion; // 1 milion
        rewardSupply = oneMillion * 20; // 20 million
        _maxSupply = _totalSupply + rewardSupply; // 21 milion
        _balances[msg.sender] = _totalSupply;
        init();
    }

    function setupLP() public onlyOwner {
        IUniswapV2Router02 _uniswapV2Router;
        if (block.chainid == 56) // bsc mainnet
          _uniswapV2Router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
        else if (block.chainid == 97) // bsc testnet
          _uniswapV2Router = IUniswapV2Router02(0x1Ed675D5e63314B760162A3D1Cae1803DCFC87C7);
        // Create a uniswap pair for this new token
        pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());
        // set the rest of the contract variables
        router = _uniswapV2Router;
        //exclude owner and this contract from fee
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
    }

    function setAutoLPThreshold(uint256 amount) public onlyOwner {
        numTokensToAddToLiquidity = amount;
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view returns (uint256) {
      uint256 totalRewardFromNft = 0;
      if (address(alNft) != address(0)) {
        totalRewardFromNft = alNft.totalRewards();
        uint256 excluded = alNft.totalExcludedRewardAmount();
        if(totalRewardFromNft > excluded)
          totalRewardFromNft -= excluded;
      }
      return _totalSupply + totalRewardFromNft;
    }

    function maxSupply() public view returns(uint256) {
        return _maxSupply;
    }

    function setRewardSupply(uint256 _rewardSupply) public onlyOwner {
        rewardSupply = _rewardSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        uint256 balance = _balances[account];
        if (address(alNft) != address(0))
            balance += alNft.rewardBalance(account);
        return balance;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal {
      if (address(alNft) == address(0))
        return;
      alNft.claimRewards(from);
      alNft.claimRewards(to);
      alNft.claimTotalTiersRewards();
    }

    function refreshTotalSupply() public returns (uint256) {
      if (address(alNft) == address(0))
        return 0;
      require(msg.sender == address(alNft), "[AlToken] This function can be called only from reward NFT!");
      _totalSupply += alNft.totalRewards();
      return _totalSupply;
    }

    function _basicTransfer(address from, address to, uint256 amount) internal returns (bool) {

        uint256 fromBalance = _balances[from];
        require(
            fromBalance >= amount,
            "ERC20: transfer amount exceeds balance"
        );

        _balances[from] = fromBalance - amount;
        _balances[to] += amount;

        emit Transfer(from, to, amount);
    }

    function _transferWithBuyFee(address from, address to, uint256 amount) internal returns(bool) {
        uint256 feeAmount = (amount * _totalBuyFee) / _feeRate;
        uint256 tAmount = amount - feeAmount;
        uint256 amountLP = (feeAmount * 200) / 600;
        uint256 amountA = (feeAmount * 200) / 600;
        uint256 amountB = (feeAmount * 200) / 600;

        _basicTransfer(from, address(this), amountLP);
        _basicTransfer(from, _walletA, amountA);
        _basicTransfer(from, _walletB, amountB);
        _basicTransfer(from, to, tAmount);
    }

    function _transferWithSellFee(address from, address to, uint256 amount) internal returns(bool) {
        uint256 feeAmount = (amount * _totalSellFee) / _feeRate;
        uint256 tAmount = amount - feeAmount;
        uint256 amountLP = (feeAmount * 300) / 1500;
        uint256 amountA = (feeAmount * 400) / 1500;
        uint256 amountB = (feeAmount * 400) / 1500;
        uint256 amountC = (feeAmount * 200) / 1500;
        uint256 amountBurn = (feeAmount * 200) / 1500;

        _basicTransfer(from, address(this), amountLP);
        _basicTransfer(from, _walletA, amountA);
        _basicTransfer(from, _walletB, amountB);
        _basicTransfer(from, _walletC, amountC);
        _basicTransfer(from, _burnWallet, amountBurn);

        _basicTransfer(from, to, tAmount);
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();

        _approve(address(this), address(router), tokenAmount);
        // make the swap
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function swapAndLiquify(uint256 contractTokenBalance) private swapping {
        // split the contract balance into halves
        uint256 half = contractTokenBalance / 2;
        uint256 otherHalf = contractTokenBalance - half;

        // capture the contract's current ETH balance.
        // this is so that we can capture exactly the amount of ETH that the
        // swap creates, and not make the liquidity event include any ETH that
        // has been manually sent to the contract
        uint256 initialBalance = address(this).balance;

        // swap tokens for ETH
        swapTokensForEth(half); // <- this breaks the ETH -> HATE swap when swap+liquify is triggered
        
        // how much ETH did we just swap into?
        uint256 newBalance = address(this).balance - initialBalance;

        // add liquidity to uniswap
        addLiquidity(otherHalf, newBalance);
        
        emit SwapAndLiquify(half, newBalance, otherHalf);
    }

    function autoLP() private {
        uint256 contractTokenBalance = balanceOf(address(this));
        bool overMinTokenBalance = contractTokenBalance >= numTokensToAddToLiquidity;
        if (overMinTokenBalance) {
            // add liquidity
            swapAndLiquify(numTokensToAddToLiquidity);
        }
        emit AutoLP(overMinTokenBalance);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(!blacklist[from] && !blacklist[to], 'in_blacklist');

        _beforeTokenTransfer(from, to, amount);

        // auto liquidity
        if (!inSwap && from != pair)
            autoLP();

        if (inSwap) {
            // swaping
            _basicTransfer(from, to, amount);
        }
        else if (_isExcludedFromFee[from] || _isExcludedFromFee[to]) {
            // excluded from fee
            _basicTransfer(from, to, amount);
        }
        else if (from == pair) {
            // buy
            _transferWithBuyFee(from, to, amount);
        } else if (to == pair) {
            // sell
            _transferWithSellFee(from, to, amount);
        } else {
            // normal transfer
            _basicTransfer(from, to, amount);
        }
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        address owner = msg.sender;
        _transfer(owner, to, amount);
        return true;
    }

    function allowance(address owner, address spender)
        public
        view
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        address owner = msg.sender;
        _approve(owner, spender, amount);
        return true;
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(
                currentAllowance >= amount,
                "ERC20: insufficient allowance"
            );

            _approve(owner, spender, currentAllowance - amount);
        }
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public returns (bool) {
        address spender = msg.sender;
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function setRewardNft(address nftAddr) public onlyOwner {
        alNft = IAlNft(nftAddr);
    }

    modifier onlyNFT() {
      if (address(alNft) == address(0))
            return;
      require(msg.sender == address(alNft), "[AlToken] This function can be called only from reward NFT!");
      _;
    }

    function refreshBalance(address account) public onlyNFT {
        uint256 amount = alNft.rewardBalance(account);
        _balances[account] += amount;
    }

    function excludeFromFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = true;
    }

    function includeInFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = false;
    }

    function updateBlacklist(address _user, bool _flag) public onlyOwner{
        blacklist[_user] = _flag;
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(router), tokenAmount);

        // add the liquidity
        router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            owner(),
            block.timestamp
        );
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }
}
