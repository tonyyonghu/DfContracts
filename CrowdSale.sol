pragma solidity ^0.4.18;

import './MultiOwnable.sol';
import './SafeMath.sol';
import './IERC20Token.sol';
import './PricingStrategy.sol';

contract CrowdSale is MultiOwnable {

    using SafeMath for uint256;

    enum ICOState {
        NotStarted,
        Started,
        Stopped,
        Finished
    } // ICO SALE STATES

    struct Stats { 
        uint256 TotalContrAmount;
        ICOState State;
        uint256 TotalContrCount;
    }

    event Contribution(address contraddress, uint256 ethamount, uint256 tokenamount);
    event PresaleTransferred(address contraddress, uint256 tokenamount);
    event TokenOPSPlatformTransferred(address contraddress, uint256 tokenamount);
    event OVISBookedTokensTransferred(address contraddress, uint256 tokenamount);
    event OVISSaleBooked(uint256 dfToken);
    event OVISReservedTokenChanged(uint256 dfToken);
    event RewardPoolTransferred(address rewardpooladdress, uint256 tokenamount);
    event OPSPoolTransferred(address OPSpooladdress, uint256 tokenamount);
    event SaleStarted();
    event SaleStopped();
    event SaleContinued();
    event SoldOutandSaleStopped();
    event SaleFinished();
    event TokenAddressChanged(address dfaddress, address OPSAddress);
    event StrategyAddressChanged(address strategyaddress);   
    event Funded(address fundaddress, uint256 amount);

    uint256 public constant MIN_ETHER_CONTR = 0.1 ether; // MINIMUM ETHER CONTRIBUTION 
    uint256 public constant MAX_ETHER_CONTR = 100 ether; // MAXIMUM ETHER CONTRIBUTION

    uint256 public constant DECIMALCOUNT = 10**18;
    uint256 public constant DF_PER_ETH = 8000; // 1 ETH = 8000 DF

    uint256 public constant PRESALE_DFTOKENS = 5000000; // PRESALE 500 ETH * 10000 DF AMOUNT
    uint256 public constant TOKENOPSPLATFORM_DFTOKENS = 25000000; // TOKENOPS PLAFTORM RESERVED AMOUNT
    uint256 public constant MAX_AVAILABLE_DFTOKENS = 100000000; // PRESALE DF TOKEN SALE AMOUNT
    uint256 public AVAILABLE_DFTOKENS = uint256(100000000).mul(DECIMALCOUNT);
     
    uint256 public OVISRESERVED_TOKENS = 25000000; // RESERVED TOKEN AMOUNT FOR OVIS PARTNER SALE
    uint256 public OVISBOOKED_TOKENS = 0;
    uint256 public OVISBOOKED_BONUSTOKENS = 0;

    uint256 public constant SALE_START_TIME = 1523059201; //UTC 2018-04-07 00:00:01

    
    uint256 public ICOSALE_DFTOKENS = 0; // ICO CONTRACT TOTAL DF SALE AMOUNT
    uint256 public ICOSALE_BONUSDFTOKENS = 0; // ICO CONTRACT TOTAL DF BONUS AMOUNT
    uint256 public TOTAL_CONTRIBUTOR_COUNT = 0; // ICO SALE TOTAL CONTRIBUTOR COUNT

    ICOState public CurrentState; // ICO SALE STATE

    IERC20Token public DfToken;
    IERC20Token public OPSToken;
    PricingStrategy public PriceStrategy;

    address public FundAddress = 0x25Bc52CBFeB86f6f12EaddF77560b02c4617DC21;
    address public RewardPoolAddress = 0xEb1FAef9068b6B8f46b50245eE877dA5b03D98C9;
    address public OvisAddress = 0x096A5166F75B5B923234841F69374de2F47F9478;
    address public PresaleAddress = 0x3e5EF0eC822B519eb0a41f94b34e90D16ce967E8;
    address public TokenOPSSaleAddress = 0x8686e49E07Bde4F389B0a5728fCe8713DB83602b;
    address public StrategyAddress = 0xe2355faB9239d5ddaA071BDE726ceb2Db876B8E2;
    address public OPSPoolAddress = 0xEA5C0F39e5E3c742fF6e387394e0337e7366a121;

    modifier checkCap() {
        require(msg.value>=MIN_ETHER_CONTR);
        require(msg.value<=MAX_ETHER_CONTR);
        _;
    }

    modifier checkBalance() {
        require(DfToken.balanceOf(address(this))>0);
        require(OPSToken.balanceOf(address(this))>0);
        _;       
    }

    modifier checkTime() {
        require(now>=SALE_START_TIME);
        _;
    }

    modifier checkState() {
        require(CurrentState == ICOState.Started);
        _;
    }

    function CrowdSale() {
        PriceStrategy = PricingStrategy(StrategyAddress);

        CurrentState = ICOState.NotStarted;
        uint256 _soldtokens = PRESALE_DFTOKENS.add(TOKENOPSPLATFORM_DFTOKENS).add(OVISRESERVED_TOKENS);
        _soldtokens = _soldtokens.mul(DECIMALCOUNT);
        AVAILABLE_DFTOKENS = AVAILABLE_DFTOKENS.sub(_soldtokens);
    }

    function() payable public checkState checkTime checkBalance checkCap {
        contribute();
    }

    /**
     * @dev calculates token amounts and sends to contributor
     */
    function contribute() private {
        uint256 _dfAmount = 0;
        uint256 _dfBonusAmount = 0;
        uint256 _dfTransferAmount = 0;
        uint256 _bonusRate = 0;
        uint256 _ethAmount = msg.value;

        if (msg.value.mul(DF_PER_ETH)>AVAILABLE_DFTOKENS) {
            _ethAmount = AVAILABLE_DFTOKENS.div(DF_PER_ETH);
        } else {
            _ethAmount = msg.value;
        }       

        _bonusRate = PriceStrategy.getRate();
        _dfAmount = (_ethAmount.mul(DF_PER_ETH));
        _dfBonusAmount = _ethAmount.mul(DF_PER_ETH).mul(_bonusRate).div(100);  
        _dfTransferAmount = _dfAmount.add(_dfBonusAmount);
        
        require(_dfAmount<=AVAILABLE_DFTOKENS);

        require(DfToken.transfer(msg.sender, _dfTransferAmount));
        require(OPSToken.transfer(msg.sender, _dfTransferAmount));     

        if (msg.value>_ethAmount) {
            msg.sender.transfer(msg.value.sub(_ethAmount));
            CurrentState = ICOState.Stopped;
            SoldOutandSaleStopped();
        }

        AVAILABLE_DFTOKENS = AVAILABLE_DFTOKENS.sub(_dfAmount);
        ICOSALE_DFTOKENS = ICOSALE_DFTOKENS.add(_dfAmount);
        ICOSALE_BONUSDFTOKENS = ICOSALE_BONUSDFTOKENS.add(_dfBonusAmount);         
        TOTAL_CONTRIBUTOR_COUNT = TOTAL_CONTRIBUTOR_COUNT.add(1);

        Contribution(msg.sender, _ethAmount, _dfTransferAmount);
    }

     /**
     * @dev book OVIS partner sale tokens
     */
    function bookOVISSale(uint256 _rate, uint256 _dfToken) onlyOwner public {              
        OVISBOOKED_TOKENS = OVISBOOKED_TOKENS.add(_dfToken);
        require(OVISBOOKED_TOKENS<=OVISRESERVED_TOKENS.mul(DECIMALCOUNT));
        uint256 _bonus = _dfToken.mul(_rate).div(100);
        OVISBOOKED_BONUSTOKENS = OVISBOOKED_BONUSTOKENS.add(_bonus);
        OVISSaleBooked(_dfToken);
    }

     /**
     * @dev changes OVIS partner sale reserved tokens
     */
    function changeOVISReservedToken(uint256 _dfToken) onlyOwner public {
        if (_dfToken > OVISRESERVED_TOKENS) {
            AVAILABLE_DFTOKENS = AVAILABLE_DFTOKENS.sub((_dfToken.sub(OVISRESERVED_TOKENS)).mul(DECIMALCOUNT));
            OVISRESERVED_TOKENS = _dfToken;
        } else if (_dfToken < OVISRESERVED_TOKENS) {
            AVAILABLE_DFTOKENS = AVAILABLE_DFTOKENS.add((OVISRESERVED_TOKENS.sub(_dfToken)).mul(DECIMALCOUNT));
            OVISRESERVED_TOKENS = _dfToken;
        }
        
        OVISReservedTokenChanged(_dfToken);
    }

      /**
     * @dev changes Df Token and OPS Token contract address
     */
    function changeTokenAddress(address _dfAddress, address _OPSAddress) onlyOwner public {
        DfToken = IERC20Token(_dfAddress);
        OPSToken = IERC20Token(_OPSAddress);
        TokenAddressChanged(_dfAddress, _OPSAddress);
    }

    /**
     * @dev changes Pricing Strategy contract address, which calculates token amounts to give
     */
    function changeStrategyAddress(address _strategyAddress) onlyOwner public {
        PriceStrategy = PricingStrategy(_strategyAddress);
        StrategyAddressChanged(_strategyAddress);
    }

    /**
     * @dev transfers presale token amounts to contributors
     */
    function transferPresaleTokens() private {
        require(DfToken.transfer(PresaleAddress, PRESALE_DFTOKENS.mul(DECIMALCOUNT)));
        PresaleTransferred(PresaleAddress, PRESALE_DFTOKENS.mul(DECIMALCOUNT));
    }

    /**
     * @dev transfers presale token amounts to contributors
     */
    function transferTokenOPSPlatformTokens() private {
        require(DfToken.transfer(TokenOPSSaleAddress, TOKENOPSPLATFORM_DFTOKENS.mul(DECIMALCOUNT)));
        TokenOPSPlatformTransferred(TokenOPSSaleAddress, TOKENOPSPLATFORM_DFTOKENS.mul(DECIMALCOUNT));
    }

    /**
     * @dev transfers token amounts to other ICO platforms
     */
    function transferOVISBookedTokens() private {
        uint256 _totalTokens = OVISBOOKED_TOKENS.add(OVISBOOKED_BONUSTOKENS);
        if(_totalTokens>0) {       
            require(DfToken.transfer(OvisAddress, _totalTokens));
            require(OPSToken.transfer(OvisAddress, _totalTokens));
        }
        OVISBookedTokensTransferred(OvisAddress, _totalTokens);
    }

    /**
     * @dev transfers remaining unsold token amount to reward pool
     */
    function transferRewardPool() private {
        uint256 balance = DfToken.balanceOf(address(this));
        if(balance>0) {
            require(DfToken.transfer(RewardPoolAddress, balance));
        }
        RewardPoolTransferred(RewardPoolAddress, balance);
    }

    /**
     * @dev transfers remaining OPS token amount to pool
     */
    function transferOPSPool() private {
        uint256 balance = OPSToken.balanceOf(address(this));
        if(balance>0) {
        require(OPSToken.transfer(OPSPoolAddress, balance));
        }
        OPSPoolTransferred(OPSPoolAddress, balance);
    }


    /**
     * @dev start function to start crowdsale for contribution
     */
    function startSale() onlyOwner public {
        require(CurrentState == ICOState.NotStarted);
        require(DfToken.balanceOf(address(this))>0);
        require(OPSToken.balanceOf(address(this))>0);       
        CurrentState = ICOState.Started;
        transferPresaleTokens();
        transferTokenOPSPlatformTokens();
        SaleStarted();
    }

    /**
     * @dev stop function to stop crowdsale for contribution
     */
    function stopSale() onlyOwner public {
        require(CurrentState == ICOState.Started);
        CurrentState = ICOState.Stopped;
        SaleStopped();
    }

    /**
     * @dev continue function to continue crowdsale for contribution
     */
    function continueSale() onlyOwner public {
        require(CurrentState == ICOState.Stopped);
        CurrentState = ICOState.Started;
        SaleContinued();
    }

    /**
     * @dev finish function to finish crowdsale for contribution
     */
    function finishSale() onlyOwner public {
        if (this.balance>0) {
            FundAddress.transfer(this.balance);
        }
        transferOVISBookedTokens();
        transferRewardPool();    
        transferOPSPool();  
        CurrentState = ICOState.Finished; 
        SaleFinished();
    }

    /**
     * @dev funds contract's balance to fund address
     */
    function getFund(uint256 _amount) onlyOwner public {
        require(_amount<=this.balance);
        FundAddress.transfer(_amount);
        Funded(FundAddress, _amount);
    }

    function getStats() public constant returns(uint256 TotalContrAmount, ICOState State, uint256 TotalContrCount) {
        uint256 totaltoken = 0;
        totaltoken = ICOSALE_DFTOKENS.add(PRESALE_DFTOKENS.mul(DECIMALCOUNT));
        totaltoken = totaltoken.add(TOKENOPSPLATFORM_DFTOKENS.mul(DECIMALCOUNT));
        totaltoken = totaltoken.add(OVISBOOKED_TOKENS);
        return (totaltoken, CurrentState, TOTAL_CONTRIBUTOR_COUNT);
    }

    function destruct() onlyOwner public {
        require(CurrentState == ICOState.Finished);
        selfdestruct(FundAddress);
    }
}