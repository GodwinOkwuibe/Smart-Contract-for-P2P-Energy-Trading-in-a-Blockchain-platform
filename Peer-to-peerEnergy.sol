pragma solidity ^0.4.25;

import "./DoubleSidedAuction.sol";

contract PeerEnergy is DoubleSidedAuction {
    //DoubleAuction interfcontract;
    uint ithTime=24;
    uint InitialTime;
	/*This struct is used to create an array that will be used to store information about 
	any particular microgrid
	Most of the variables here are exactly named with what they do*/
	struct Grid {
        uint totalProduction; 
		uint totalConsumption;
		uint StartTime;
		uint priceType;//1 represent DP while 2 represent MCP
        uint[] EngyMktConsensus;	// Euro cent per Wh
		address[] usrs;				// user addresses
        uint ResetTime;
        uint[][] ESp; 				// Nested array for each timestep a separate sorted energy sell price array
        uint[][] ESq;				// Nested array for each timestep for the energy sell quantity
        address[][] ESaddr; 		// Nested array for each timestep for the sorted sell addresses (according to ESp)
        uint[][] EBp; 				// Nested array for each timestep a separate sorted energy buy price array
        uint[][] EBq; 				// Nested array for each timestep for the energy buy quantity
        address[][] EBaddr;			// Nested array for each timestep for the sorted buy addresses (according to ESp)
        uint utilitySellPrice;
	    uint utilityBuyPrice;
	    address [][] matchedBuyer;
	    address [][] matchedSeller;
	    uint [][] soldQuantity;
	    uint [][] soldPrice;
        uint []matchedLength; 
	}

	/* This modifier is use to put restrictions on the price of energy to be set by the prosumer 	*/
	modifier AskEnergyRequirements (uint _price){
	    require(users[userAddresstoID[AppToSmartmeter[msg.sender]]].typeOfUser==2 && 
		_price<grids[gridIDToNo[users[userAddresstoID[AppToSmartmeter[msg.sender]]].gridNo]].utilitySellPrice,
		"Not a Prosumer or Price not within the range");
	    _;
	}

	/* This modifier is use to put restrictions on the price of energy to be set by a consumers
	and the quatity due to the amount of token he or she has 	*/
	modifier BidEnergyRequirements (uint _qty, uint _price){
		uint amt= _qty*_price*Token_rate*3600;
	    require(Checkbalance(AppToSmartmeter[msg.sender])>=amt && _price>grids[gridIDToNo[users[userAddresstoID[AppToSmartmeter[msg.sender]]].gridNo]].utilityBuyPrice, "Not enough balance or Price not within the range");
	    _;
	}

	/* This modifier is use to check if a user has alreadzy been registered to avoid repetation */
	modifier CheckIfUserExist(address _userSMAddr, address _userAppAddr){
	   require(_userSMAddr != AppToSmartmeter[_userAppAddr] && _userSMAddr != _userAppAddr && _userSMAddr != Utility && _userAppAddr != Utility, "User Already Exist");
	   _;
	}

	modifier CheckIfUserdoesntExist(address _SMtMeter, address _UseApp){
	   require(_SMtMeter==AppToSmartmeter[_UseApp],"User Does not Exist");
	   _;
	}


	modifier CheckIfGridExist(uint gridNM){
	   require(gridNoToID[gridIDToNo[gridNM]]!=gridNM,"Grid Already Exist");
	   _;
	}
	modifier CheckIfGridDoesntExist(uint gridNM){
	   require(gridNoToID[gridIDToNo[gridNM]]==gridNM,"Grid Does Not Exist");
	   _;
	}
	Grid[] public grids; // time of energy consumption
	uint public Token_rate= 1;//token per euro cent (currently 1000token per cent)
	                          // This is because bids and asks are in cent per kWh

	uint userBalTime=(1440/ithTime);//grid will be balanced every 15 minutes
	uint public gridbalancetime=userBalTime;


	mapping (uint => uint) public gridNoToID;	// This is special number to be assigned to a particular grid
    mapping (uint => uint) public gridIDToNo;	// The grid id is the index used to address grids in an array
						// number of timesteps per day

    mapping (address => uint) public userIDtoAddrInMG; // This is used to map each participant's address to their ID within the specific microgrid


	/*This function is use to create a user to participate in energy trading*/
	function createUser(address SmartmeterAddr,address AppNodeAddr, uint _typeOfUser,uint _gridNo) public 
                        CheckIfUserExist(SmartmeterAddr, AppNodeAddr) onlyOwner() CheckIfGridDoesntExist(_gridNo) {
        uint _id = users.push(User(_typeOfUser,_gridNo,0,0,grids[gridIDToNo[_gridNo]].StartTime,new uint[](0),new uint[][](0),new uint[][](0),
        new uint[](0),0,1,0)) -1 ;
        userIDtoAddress[_id]= SmartmeterAddr;
        userAddresstoID[SmartmeterAddr]=_id;
        grids[gridIDToNo[_gridNo]].usrs.push(SmartmeterAddr); 
        grids[gridIDToNo[_gridNo]].EngyMktConsensus.push(1);							// Create new slot for user in market consensus and initialize by 1 (1=true, 0=false)
        userIDtoAddrInMG[SmartmeterAddr] = grids[gridIDToNo[_gridNo]].usrs.length-1;	// Assigns specific user ID within microgrid, -2 because solidity starts at 0 and utility is first user which is not considered
        _insertNewUser(_gridNo,SmartmeterAddr);
        _initializeBuyQty(SmartmeterAddr);
        AppToSmartmeter[AppNodeAddr]=SmartmeterAddr;
        if(users[userAddresstoID[SmartmeterAddr]].typeOfUser==2){
            _initializesSeller(SmartmeterAddr);
        }
        _initialSort(_gridNo);
    }


	function changeUserType(address SmartmeterAddr,address AppNodeAddr) public onlyOwner() CheckIfUserdoesntExist(SmartmeterAddr, AppNodeAddr){
    	users[userAddresstoID[SmartmeterAddr]].typeOfUser=2;
    	_initializesSeller(SmartmeterAddr);    
	} 


	/*This function is used to create a microgrid. The grid number and the generator address are the component required.*/
	function createGrid(uint _GridNo, uint _priceType) public onlyOwner() CheckIfGridExist(_GridNo) {
        uint _Gid = grids.push(Grid(0,0,now,_priceType,new uint[](0),new address[](0),
        now,new uint[][](0),new uint[][](0),new address[][](0),new uint[][](0),new uint[][](0)
        ,new address[][](0), 15,2, 
        new address[][](0), new address[][](0),new uint[][](0), new uint[][](0), new uint[](0))) -1 ;
        gridNoToID[_Gid]= _GridNo;
        gridIDToNo[_GridNo]=_Gid;
        grids[gridIDToNo[_GridNo]].usrs.push(Utility); 
        grids[gridIDToNo[_GridNo]].EngyMktConsensus.push(1);	
        _insertGridUtility(_GridNo);
    }


    /*This function sets the consumption or the production of the smart meter
    _consumedProduced Energy = energy produced or consumed in Ws
    flag: 1 for consumption, 2 for production*/
	function setMeterData(uint _consumedProducedEnergy, uint flag) public OnlySmartMeter(msg.sender) {
        if(now >= (users[userAddresstoID[msg.sender]].time+userBalTime))  {//29 mins 30 secs
		     _balanceUser();
        } 
		_payUserDebt(msg.sender);
	    if(users[userAddresstoID[msg.sender]].RelayState==1)  {
            if(flag == 1) {
                users[userAddresstoID[msg.sender]].consumedEnergy +=  _consumedProducedEnergy;
                grids[gridIDToNo[users[userAddresstoID[msg.sender]].gridNo]].totalConsumption += 
                _consumedProducedEnergy;
            }
            if(flag == 2) {
                users[userAddresstoID[msg.sender]].producedEnergy +=  _consumedProducedEnergy;
                grids[gridIDToNo[users[userAddresstoID[msg.sender]].gridNo]].totalProduction += 
                _consumedProducedEnergy;
            }
	    }
    }


	/*This function is used by the Owner to set the exchange rate from euro to token*/
	function setExchangeRate(uint _rate) public onlyOwner() {
        Token_rate = _rate;
    }


    /*This function balances production and consumption of the*/
    function _balanceUser() internal {
        _balanceUserConsumption();
        if (users[userAddresstoID[msg.sender]].typeOfUser==2){
		    _balanceUserProduction();    

        } else{
            users[userAddresstoID[msg.sender]].producedEnergy =0;
        }   
		grids[gridIDToNo[users[userAddresstoID[msg.sender]].gridNo]].EngyMktConsensus[userIDtoAddrInMG[msg.sender]]=1;
		_resetGridTime(users[userAddresstoID[msg.sender]].gridNo); 
		if (now >= userBalTime + grids[gridIDToNo[users[userAddresstoID[msg.sender]].gridNo]].StartTime){
		    _resetBalGrid(users[userAddresstoID[msg.sender]].gridNo);
		}
    }


    /*This function is use to set the start time for participants within the grid to start 
    trading after they have arrived to concencus*/
    function _resetGridTime(uint locgridN)internal {
        if(now>=grids[gridIDToNo[locgridN]].ResetTime + userBalTime){
            while(now>=grids[gridIDToNo[locgridN]].ResetTime + userBalTime){
                users[userAddresstoID[msg.sender]].time=gridbalancetime + grids[gridIDToNo[locgridN]].ResetTime;
                grids[gridIDToNo[locgridN]].ResetTime+=gridbalancetime;
            }
        }
        else {
            users[userAddresstoID[msg.sender]].time=grids[gridIDToNo[locgridN]].ResetTime;
        }
    }


    /*This function is used to restart the trade time at any instant by the owner. 
    It is also used to start the trade after a participants are set to avoid clearing the market without 
    before trading*/
    function restartTrade() public onlyAlarm(){
        uint i;InitialTime=now;
        for( i=0; i<grids.length; i++) 	{
            grids[i].StartTime=now;
		    grids[i].ResetTime=now;
		}
        for( i=0; i<users.length; i++) {
		    users[i].time=now;
		}
    }


    /*This function is used to set the use balance time in minutes. example, 30=(30 minutes)*/
    function changeGridBalTime(uint _TimeInMinutes) public onlyOwner() {
        userBalTime = (_TimeInMinutes-1)*60;
        gridbalancetime = _TimeInMinutes*60;
    }


    /*The function is used to set relay state based on the recieved logic
    true: set relat on by sending 1
    false: set relay off by sending 0
    Outstanding bills of the participants are added as losses to the participants so 
    as to pay for it on calling of function setMeterData*/
    function _setRelayState(bool logic,uint _amtTopay) internal{
        if(logic==true) {
            users[userAddresstoID[msg.sender]].RelayState=1;       
        }
        else{
		    users[userAddresstoID[msg.sender]].RelayState=0;
		    users[userAddresstoID[msg.sender]].userDebt +=_amtTopay;  
		}
		uint itT = _getIterationIndex();
	    users[userAddresstoID[msg.sender]].BQty[itT]=0;
        users[userAddresstoID[msg.sender]].consumedEnergy=0;
    }


    /*This function is use by the smart meter to view their relay state at any instant*/
    function viewRelayState(address SMadress) public view returns(uint) {
        return users[userAddresstoID[SMadress]].RelayState;
    }


    /*This function calculates and transfers all tokens for losses on the microgrid*/
    function _payUserDebt(address _user) internal  {
	    if (users[userAddresstoID[msg.sender]].userDebt>0){   
            uint debtprice1=((users[userAddresstoID[_user]].userDebt)/3600)+1;
            debtprice1=debtprice1*Token_rate*grids[gridIDToNo[users[userAddresstoID[_user]].gridNo]].utilitySellPrice;
            if (debtprice1>0 && balanceOf[msg.sender] > debtprice1){
               transfer(Utility, debtprice1);
	           users[userAddresstoID[_user]].userDebt=0;      
	           users[userAddresstoID[_user]].RelayState=1;
	        }
	        if(debtprice1>0 && balanceOf[msg.sender] < debtprice1) {
	           users[userAddresstoID[_user]].RelayState=0;
		    } 
	    }
    }


    /*This function is use to set the generator sell and buy price for each grid*/
    function setUtilitySellBuyPrice(uint Sellprice, uint BuyPrice, uint _gridNu) public OnlyUtility (msg.sender) {   
        grids[gridIDToNo[_gridNu]].utilitySellPrice=Sellprice;
        grids[gridIDToNo[_gridNu]].utilityBuyPrice=BuyPrice;
    }


	/*If the consumers has bought energy from a fellow prosumer but has not consumed it, 
	the utility will buy the excess energy of the prosumer and refund its OWN buy price to the consumer. 
	The prosumer already got his reward when his smart measured his delivery into the grid.
	This function therefore transfers the tokens from the utility to the consumer account and sets the utility debt to zero. */
	function _payUtilityDebt(uint _gridNu) internal {
	    uint i;
	    if(msg.sender == ExchangeAddr) {
			for( i = 0; i < grids[gridIDToNo[_gridNu]].usrs.length; i++) {  
				if (transferFrom(Utility, grids[gridIDToNo[users[userAddresstoID[msg.sender]].gridNo]].usrs[i], users[userAddresstoID[grids[gridIDToNo[users[userAddresstoID[msg.sender]].gridNo]].usrs[i]]].UtilityDebt) == true){ 
					users[userAddresstoID[grids[gridIDToNo[users[userAddresstoID[msg.sender]].gridNo]].usrs[i]]].UtilityDebt = 0;
				}
            }
	    }
	}


	/*This function is used by the user to know how much energy he bought from the market*/
	function viewQtyBought(address AppAddr) public view returns(uint[]){
	    uint cIndex=_getIterationIndex();
	    uint cnt=cIndex;
	    uint cnt2=0;
	    uint index=ithTime;
	    uint[] memory EnergyBQty = new uint[] (index);        
        for(uint i=0; i<index; i++){
            if (cIndex<index){
            EnergyBQty[i]=users[userAddresstoID[AppToSmartmeter[AppAddr]]].BQty[cIndex]; 
            cIndex++;

            }
            else{
                if (cnt2<cnt){
                    EnergyBQty[i]=users[userAddresstoID[AppToSmartmeter[AppAddr]]].BQty[cnt2]; 
                    cnt2++;
                }
            }



        }
        return EnergyBQty ;
	}


	/*This function is used by the user to know how much energy he was matche from the market to deliver
	for any of the time step*/
	function viewQtySoldAndPrice(address AppAddr, uint _tim) public view returns (uint[] Energy,uint[] Prices){
	    uint l=0;
	    if (users[userAddresstoID[AppToSmartmeter[AppAddr]]].sellcount[_tim]>users[userAddresstoID[AppToSmartmeter[AppAddr]]].SQty[_tim].length){
	        l=users[userAddresstoID[AppToSmartmeter[AppAddr]]].SQty[_tim].length;

	    }
	    else{
	        l=users[userAddresstoID[AppToSmartmeter[AppAddr]]].sellcount[_tim];
	    }
	    users[userAddresstoID[AppToSmartmeter[AppAddr]]].sellcount[_tim];
	    uint[] memory EnergySoldQty = new uint[] (l); 
	    uint[] memory EnergySoldPrice = new uint[] (l); 
	    for(uint i=0; i<l; i++){
	        EnergySoldQty[i]=users[userAddresstoID[AppToSmartmeter[AppAddr]]].SQty[_tim][i];
	        EnergySoldPrice[i]=users[userAddresstoID[AppToSmartmeter[AppAddr]]].SPrice[_tim][i];
	    }
	    return (EnergySoldQty,EnergySoldPrice);
	}


	/*This function is used to reset the grid time after balancing the 
	production and losses*/
	function _resetBalGrid(uint _gridNUmm) internal {
		    grids[gridIDToNo[_gridNUmm]].StartTime =grids[gridIDToNo[_gridNUmm]].ResetTime;   
		    grids[gridIDToNo[_gridNUmm]].totalProduction =0;
		    grids[gridIDToNo[_gridNUmm]].totalConsumption=0;
	}


	/*This is use to bid energy a user is willing to provide to another user
	_price: euro cent/kWh
	_Qty: Wh quantity the user can produce in the next 15mins*/
	function placeSellOffer(uint _price, uint _Qty, uint _tim ) public OnlyAppNode(msg.sender) AskEnergyRequirements(_price) 
	{
	    uint _GridNo=users[userAddresstoID[AppToSmartmeter[msg.sender]]].gridNo;
	    uint indxS=_getArrayIndex(grids[gridIDToNo[_GridNo]].ESaddr[_tim], AppToSmartmeter[msg.sender]);
	    uint indxB=	_getArrayIndex(grids[gridIDToNo[_GridNo]].EBaddr[_tim], AppToSmartmeter[msg.sender]);
	    grids[gridIDToNo[users[userAddresstoID[AppToSmartmeter[msg.sender]]].gridNo]].ESq[_tim][indxS]=_Qty;
	    grids[gridIDToNo[users[userAddresstoID[AppToSmartmeter[msg.sender]]].gridNo]].EBq[_tim][indxB]=0;
	    grids[gridIDToNo[users[userAddresstoID[AppToSmartmeter[msg.sender]]].gridNo]].ESp[_tim][indxS]=_price;
        _sortSellOffers(users[userAddresstoID[AppToSmartmeter[msg.sender]]].gridNo, _tim);
        _sortBuyOffers(users[userAddresstoID[AppToSmartmeter[msg.sender]]].gridNo, _tim);
	}


	/*This is use to ask for energy a user is willing to consume from another user
	_price: euro/kWh
	_Qty: Wh quantity the user can  in the next 15mins*/
	function placeBuyOffer(uint _price, uint _Qty, uint _tim ) public  OnlyAppNode(msg.sender)BidEnergyRequirements (_Qty,_price) 	{ 
	    uint _GridNo=users[userAddresstoID[AppToSmartmeter[msg.sender]]].gridNo;
	    uint indxS=_getArrayIndex(grids[gridIDToNo[_GridNo]].ESaddr[_tim], AppToSmartmeter[msg.sender]);
	    uint indxB=	_getArrayIndex(grids[gridIDToNo[_GridNo]].EBaddr[_tim], AppToSmartmeter[msg.sender]);
	    grids[gridIDToNo[users[userAddresstoID[AppToSmartmeter[msg.sender]]].gridNo]].EBq[_tim][indxB]=_Qty;
	    grids[gridIDToNo[users[userAddresstoID[AppToSmartmeter[msg.sender]]].gridNo]].ESq[_tim][indxS]=0;
	    grids[gridIDToNo[users[userAddresstoID[AppToSmartmeter[msg.sender]]].gridNo]].EBp[_tim][indxB]=_price;
	    _sortSellOffers(users[userAddresstoID[AppToSmartmeter[msg.sender]]].gridNo, _tim);
	    _sortBuyOffers(users[userAddresstoID[AppToSmartmeter[msg.sender]]].gridNo, _tim);
	}


	/*use to sort energy bid*/
	function _sortSellOffers(uint _GridNo,uint _tim) internal  {
		(grids[gridIDToNo[_GridNo]].ESp[_tim],grids[gridIDToNo[_GridNo]].ESq[_tim],
		grids[gridIDToNo[_GridNo]].ESaddr[_tim]) = 
		_sortSellPrices(grids[gridIDToNo[_GridNo]].ESp[_tim],grids[gridIDToNo[_GridNo]].ESq[_tim],
		grids[gridIDToNo[_GridNo]].ESaddr[_tim]);
    }


    /*use to sort energy ask*/
    function _sortBuyOffers(uint _GridNo, uint _tim) internal  {
        (grids[gridIDToNo[_GridNo]].EBp[_tim],grids[gridIDToNo[_GridNo]].EBq[_tim], 
        grids[gridIDToNo[_GridNo]].EBaddr[_tim]) = 
        _sortBuyPrices(grids[gridIDToNo[_GridNo]].EBp[_tim],grids[gridIDToNo[_GridNo]].EBq[_tim], 
        grids[gridIDToNo[_GridNo]].EBaddr[_tim]);
    }


    /*This functio is use to return the energy bids that the prosumers on each grid wish to sell*/
    function viewSellOffers(uint _GridNo,uint _tim) public view  returns (uint[] Sell_Price, uint[] Sell_Qty) {
        return (grids[gridIDToNo[_GridNo]].ESp[_tim], grids[gridIDToNo[_GridNo]].ESq[_tim]); 
    }


    /*This functio is use to return the energy ask that the consumers on each grid wish to buy*/
    function viewBuyOffers(uint _GridNo, uint _tim) public view   returns (uint[] Buy_Price, uint[] Buy_Qty) {

        return (grids[gridIDToNo[_GridNo]].EBp[_tim], grids[gridIDToNo[_GridNo]].EBq[_tim]); 
    }


    function viewMatchedEnergy(uint _GridNo, uint _tim) public view   returns (address[] Buyer_Addr, address[] Seller_Addr, uint[] Matched_Qty, uint[] Price) {
        uint256 l = grids[gridIDToNo[_GridNo]].matchedLength[_tim];
        address[] memory Buyer = new address[] (l);
        address[] memory Seller = new address[] (l);
        uint[] memory Av_Qty = new uint[] (l);   
        uint[] memory Av_Price = new uint[] (l);        
        for(uint i=0; i<l; i++){
            Buyer[i] = grids[gridIDToNo[_GridNo]].matchedBuyer[_tim][i];
            Seller[i] = grids[gridIDToNo[_GridNo]].matchedSeller[_tim][i];
            Av_Qty[i] = grids[gridIDToNo[_GridNo]].soldQuantity[_tim][i];
            Av_Price[i]=grids[gridIDToNo[_GridNo]].soldPrice[_tim][i];
        }
        return (Buyer, Seller, Av_Qty, Av_Price); 
    }


    /*This function is used to call the match bids one grid after the other*/
	function clearEnergyOrder(address memberAddr) public onlyAlarm() { 
	    uint Gridnun=users[userAddresstoID[memberAddr]].gridNo;
		if (viewMarketConsensus(Gridnun)==true){
			for (uint ith=0; ith<ithTime;ith++){  
				_matchBuyAndSellOffers(Gridnun, ith);
			}
        _resetMarketConsensus(Gridnun);
        _payUtilityDebt(Gridnun);
       }
    }


    uint r; uint j;       uint _mcp;//use to count iterations




    /* Removes matched offers after market clearing */
    function _remMatchedOffers(uint _GridNo, uint _ith) internal  {
        for (uint i = 0; i < grids[gridIDToNo[_GridNo]].soldQuantity[_ith].length; i++){   
            grids[gridIDToNo[_GridNo]].soldQuantity[_ith][i] = 0;    
        }
        grids[gridIDToNo[_GridNo]].matchedLength[_ith] = 0; 
    } 


    /*use to mach energy oders*/
    function _matchBuyAndSellOffers(uint _GridNo, uint _ith) internal  {
        uint df;
        uint y=1; 
       r =0; j=0; 
        uint Avp1; uint Avq1;uint Amt;
        uint itT=_getCurrentIteration();
	    if (_ith==itT){
	        _remMatchedOffers( _GridNo, _ith);   
	    }
        if (grids[gridIDToNo[_GridNo]].priceType==2){
       _mcp= _determineMCP(grids[gridIDToNo[_GridNo]].ESp[_ith], grids[gridIDToNo[_GridNo]].ESq[_ith], 
        grids[gridIDToNo[_GridNo]].EBp[_ith],grids[gridIDToNo[_GridNo]].EBq[_ith],grids[gridIDToNo[_GridNo]].EBaddr[_ith]);
        }
        while(y>0 && j<grids[gridIDToNo[_GridNo]].EBp[_ith].length && r< grids[gridIDToNo[_GridNo]].ESp[_ith].length){
	        if(grids[gridIDToNo[_GridNo]].ESp[_ith][r]<= grids[gridIDToNo[_GridNo]].EBp[_ith][j]) {
		        if (grids[gridIDToNo[_GridNo]].ESq[_ith][r] == grids[gridIDToNo[_GridNo]].EBq[_ith][j]){
                    Avp1 = (grids[gridIDToNo[_GridNo]].ESp[_ith][r] + grids[gridIDToNo[_GridNo]].EBp[_ith][j])/2;
                    Avq1 = grids[gridIDToNo[_GridNo]].ESq[_ith][r];
                    if (Avq1==0){
                     j++; r++;
                    } 
                    else {
                        Amt =Avp1*Avq1*Token_rate;
                        if (balanceOf[grids[gridIDToNo[_GridNo]].EBaddr[_ith][j]]>Amt ){
                              if (grids[gridIDToNo[_GridNo]].priceType==2){
                                    _assignMatchedPrice( _mcp, Avq1, _GridNo, _ith,r,j); 
                              }
                              else{
                                     _assignMatchedPrice( Avp1, Avq1, _GridNo, _ith,r,j);
                              }


                            grids[gridIDToNo[_GridNo]].ESq[_ith][r]=0;
                            r++; 
                        }
                    grids[gridIDToNo[_GridNo]].EBq[_ith][j]=0;
                    j++;
		            }
		        }
		        else if (grids[gridIDToNo[_GridNo]].ESq[_ith][r] > grids[gridIDToNo[_GridNo]].EBq[_ith][j]){
		        df= grids[gridIDToNo[_GridNo]].ESq[_ith][r] - grids[gridIDToNo[_GridNo]].EBq[_ith][j];
	            Avp1 = (grids[gridIDToNo[_GridNo]].ESp[_ith][r] + grids[gridIDToNo[_GridNo]].EBp[_ith][j])/2;
		             Avq1 = grids[gridIDToNo[_GridNo]].EBq[_ith][j];
		             if (Avq1==0){
		                j++; 
		             } 
		             else {
                        Amt =Avp1*Avq1*Token_rate;
                        if (balanceOf[grids[gridIDToNo[_GridNo]].EBaddr[_ith][j]]>Amt ){
                              if (grids[gridIDToNo[_GridNo]].priceType==2){
                                    _assignMatchedPrice( _mcp, Avq1, _GridNo, _ith,r,j); 
                              }
                              else{
                                     _assignMatchedPrice( Avp1, Avq1, _GridNo, _ith,r,j);
                              }
                            grids[gridIDToNo[_GridNo]].ESq[_ith][r]= df; 

                            }
                    grids[gridIDToNo[_GridNo]].EBq[_ith][j]=0; 
                    j++;
                    }
		        }
	            else {
		             df=grids[gridIDToNo[_GridNo]].EBq[_ith][j] - grids[gridIDToNo[_GridNo]].ESq[_ith][r] ;
	        	     Avp1 = (grids[gridIDToNo[_GridNo]].ESp[_ith][r] + grids[gridIDToNo[_GridNo]].EBp[_ith][j])/2;
		             Avq1=  grids[gridIDToNo[_GridNo]].ESq[_ith][r];
		             if (Avq1==0){
		                 r++;
		             } 
		             else {
		                Amt =Avp1*Avq1*Token_rate;
		                if (balanceOf[grids[gridIDToNo[_GridNo]].EBaddr[_ith][j]]>Amt ){
                              if (grids[gridIDToNo[_GridNo]].priceType==2){
                                    _assignMatchedPrice( _mcp, Avq1, _GridNo, _ith,r,j); 
                              }
                              else{
                                     _assignMatchedPrice( Avp1, Avq1, _GridNo, _ith,r,j);
                              }
                            grids[gridIDToNo[_GridNo]].EBq[_ith][j]= df; 
                            grids[gridIDToNo[_GridNo]].ESq[_ith][r]=0;
                            r++;
                        }
                    }
	            }
        	}
        	else{
        	    y=0;

	            itT=_getCurrentIteration();
	            if (_ith==itT){
	                _remUnmatchedOffers( _GridNo, _ith);
                }
        	    _sortSellOffers(_GridNo,_ith);
	            _sortBuyOffers(_GridNo, _ith);

    	    }
        }
    }

   /*This function is used to determine the Market clearing price*/
    function _determineMCP(uint[] sellPrice, uint[] sellQty, 
        uint[] buyPrice,uint[] buyQty,address [] buyAddr) internal returns(uint _Mcp){
        uint df;
        uint y=1; 
       r =0; j=0; 
        uint Avp1; uint Avq1;uint Amt;
        while(y>0 && j<buyPrice.length && r< sellPrice.length){
	        if(sellPrice[r]<= buyPrice[j]) {
		        if (sellQty[r] == buyQty[j]){
                    Avp1 = (sellPrice[r] + buyPrice[j])/2;
                    Avq1 = sellQty[r];
                    if (Avq1==0){
                     j++; r++;
                    } 
                    else {
                        Amt =Avp1*Avq1*Token_rate;
                        if (balanceOf[buyAddr[j]]>Amt ){
                            sellQty[r]=0;
                            r++; 
                        }
                    buyQty[j]=0;
                    j++;
		            }
		        }
		        else if (sellQty[r] > buyQty[j]){
		        df= sellQty[r] - buyPrice[j];
	            Avp1 = (sellPrice[r] + buyPrice[j])/2;
		             Avq1 = buyQty[j];
		             if (Avq1==0){
		                j++; 
		             } 
		             else {
                        Amt =Avp1*Avq1*Token_rate;
                        if (balanceOf[buyAddr[j]]>Amt ){
                            sellQty[r]= df; 

                            }
                    buyQty[j]=0; 
                    j++;
                    }
		        }
	            else {
		             df=buyQty[j] - sellQty[r] ;
	        	     Avp1 = (sellPrice[r] + buyPrice[j])/2;
		             Avq1=  sellQty[r];
		             if (Avq1==0){
		                 r++;
		             } 
		             else {
		                Amt =Avp1*Avq1*Token_rate;
		                if (balanceOf[buyAddr[j]]>Amt ){
                            buyQty[j]= df; 
                            sellQty[r]=0;
                            r++;
                        }
                    }
	            }
        	}
        	else{
        	    y=0;

    	    }
        }
        _mcp=Avp1;

       return _mcp;
    }




    /* Removes unmatched offers from market */
    function _remUnmatchedOffers(uint _GridNo, uint _ith) internal  {
	    for (uint i=0; i<grids[gridIDToNo[_GridNo]].ESq[_ith].length;i++){   
	        grids[gridIDToNo[_GridNo]].ESq[_ith][i] = 0;    
	    }
	    for ( i=0; i<grids[gridIDToNo[_GridNo]].EBq[_ith].length;i++){   
	        grids[gridIDToNo[_GridNo]].EBq[_ith][i] = 0;    
	    }
    }


	/* This function initializes the storage for buy and sell offers of a user */
	function _insertNewUser(uint gridNo,address _sMaddr) internal {
	    for (uint ith=0; ith<ithTime;ith++){  
			grids[gridIDToNo[gridNo]].ESp[ith].push(grids[gridIDToNo[gridNo]].utilitySellPrice-1);
			grids[gridIDToNo[gridNo]].ESq[ith].push(0);
			grids[gridIDToNo[gridNo]].EBp[ith].push(grids[gridIDToNo[gridNo]].utilityBuyPrice+1);
			grids[gridIDToNo[gridNo]].EBq[ith].push(0);
			grids[gridIDToNo[gridNo]].EBaddr[ith].push(_sMaddr);
			grids[gridIDToNo[gridNo]].ESaddr[ith].push(_sMaddr);
	    }
    }


	/*This function is used to push the initial bid and ask of a grid utility into the array*/
	function _insertGridUtility(uint gridNo) internal {
	    for (uint ith=0; ith<ithTime;ith++){  
			grids[gridIDToNo[gridNo]].matchedBuyer.push([0]);
			grids[gridIDToNo[gridNo]].matchedSeller.push([0]);
			grids[gridIDToNo[gridNo]].soldQuantity.push([0]);
			grids[gridIDToNo[gridNo]].soldPrice.push([0]);
			grids[gridIDToNo[gridNo]].matchedLength.push(0);
			grids[gridIDToNo[gridNo]].ESp.push([grids[gridIDToNo[gridNo]].utilitySellPrice]);
			grids[gridIDToNo[gridNo]].ESq.push([99999999999999]);
			grids[gridIDToNo[gridNo]].EBp.push([grids[gridIDToNo[gridNo]].utilityBuyPrice]);
			grids[gridIDToNo[gridNo]].EBq.push([99999999999999]);
			grids[gridIDToNo[gridNo]].EBaddr.push([Utility]);
			grids[gridIDToNo[gridNo]].ESaddr.push([Utility]);
        }
    }


    /*This is use to view the generator sell and ask price for each grid*/
    function viewGridSellBuyPrice(uint _GridNo) public  view returns(uint GenSellPrice, uint GenBuyPrice){
        return(grids[gridIDToNo[_GridNo]].utilitySellPrice, grids[gridIDToNo[_GridNo]].utilityBuyPrice);
    }


    /*This function sets the initial sell quantity and price of a prosumer.
    This will all be set as zero in the array so as to have a value in it*/
    function _initializesSeller(address UserAddr) internal {
        uint i;
        for (uint ith = 0; ith < ithTime; ith++){ 
            users[userAddresstoID[UserAddr]].SQty.push([0]);
            users[userAddresstoID[UserAddr]].SPrice.push([0]);
        }
        for (i = 1; i < grids[gridIDToNo[users[userAddresstoID[UserAddr]].gridNo]].usrs.length; i++){
            for (ith=0; ith<ithTime;ith++){ 
                users[userAddresstoID[grids[gridIDToNo[users[userAddresstoID[UserAddr]].gridNo]].usrs[i]]].SQty[ith].push(0);
                users[userAddresstoID[grids[gridIDToNo[users[userAddresstoID[UserAddr]].gridNo]].usrs[i]]].SPrice[ith].push(0); 
                }
        }
        for( i=0; i<grids[gridIDToNo[users[userAddresstoID[UserAddr]].gridNo]].usrs.length-1; i++){
              for (ith=0; ith<ithTime;ith++){  
            users[userAddresstoID[UserAddr]].SQty[ith].push(0);
            users[userAddresstoID[UserAddr]].SPrice[ith].push(0);   
            users[userAddresstoID[UserAddr]].sellcount.push(0);             
            }
        }
    }


    /* Initializes the storage for the buy quantity in the users array	*/    
    function _initializeBuyQty(address UserAddr) internal {
        for (uint ith=0; ith<ithTime;ith++){ 
            users[userAddresstoID[UserAddr]].BQty.push(0);
        } 
    }


    /*This works like the modifier onlysmartmeter but is used by the external 
    contract alarmclock to check if a user is smartmeter as it cannot access the modifier onlysmartmeter*/
    function checkSMNode(address _addrs) public view onlyAlarm() returns(bool){
        if(_addrs==userIDtoAddress[userAddresstoID[_addrs]]){
            return true;
        }
        else{return false;}
    }


    /*This function is use by the Blockchain ownwer to set the address of the alarmclock*/
	function setUtilityAddr (address _UtiAddr) public onlyOwner() returns(bool) {
        Utility=   _UtiAddr;
	    return true;
	}


	function setExchangeAddr(address _ExchAddr) public onlyOwner() returns(bool) {
	    ExchangeAddr = _ExchAddr;
	    return true;
	}	 



    /*This function is use by the alarmclock to know if there is consensus to clear the energy market*/
    function viewMarketConsensus(uint _gridNum) public view onlyAlarm() returns(bool){
        uint McountConsencus=0;
        for (uint i=0; i<grids[gridIDToNo[_gridNum]].EngyMktConsensus.length;i++){
            McountConsencus += grids[gridIDToNo[_gridNum]].EngyMktConsensus[i];
        }
        uint percentAgreeM = (McountConsencus*100)/(grids[gridIDToNo[_gridNum]].EngyMktConsensus.length);
        if(percentAgreeM>=51){
            return true;
        }
        else{return false;}
    }


    /* This is used by the alarmclock to remove consensus after clearing the energy market*/ 
    function _resetMarketConsensus(uint _gridNum) internal  {
        for (uint i=1; i<grids[gridIDToNo[_gridNum]].EngyMktConsensus.length;i++){
           grids[gridIDToNo[_gridNum]].EngyMktConsensus[i] = 0;
        }
    }


    /* This is used to publicly view the energy produced or consumed within a microgrid by the prosumers and consumers	*/    
    function viewgridProducedConsumedEnergy(uint _gridNum) public view returns(uint, uint)  {
        return (grids[gridIDToNo[_gridNum]].totalProduction,
               grids[gridIDToNo[_gridNum]].totalConsumption);
    }


	/* This is use to view the energy produced and consumed by a user at current time step	*/    
    function viewUserProducedConsumedEnergy(address _userSMaddr) public view returns(uint, uint)  {    
        return (users[userAddresstoID[_userSMaddr]].producedEnergy,
               users[userAddresstoID[_userSMaddr]].consumedEnergy);
    }


	/* This function is use to calculate the current time step using unix time	*/

	/*
	function _getIterationIndex() internal view returns(uint){
	    uint itTim;
		uint it_Time=grids[gridIDToNo[users[userAddresstoID[msg.sender]].gridNo]].StartTime/86400;   
		uint itV=grids[gridIDToNo[users[userAddresstoID[msg.sender]].gridNo]].StartTime-it_Time*86400 ; 
		uint divValue = (86400/ithTime);
		it_Time=itV/divValue;
		if (it_Time==0){
		    itTim=ithTime-1;
		}
		else{
		   itTim= it_Time-1;
		}
		return itTim;  
	}
    */
    /*This new function _getIterationIndex is use for only the purpose of simulation to reduce the simulation time. Hence the main one is commented out.
    For the simultion, one second simulation time means one minute real life time. For 24 time steps, the markets clears every minute. This means that 24 minutes 
    simulation time means a day in real life*/


    function _getIterationIndex() internal view returns(uint previous){
        uint itTim;
		uint it_Time=now-InitialTime;   
		uint itV=it_Time/1440; 
		uint divValue =it_Time-1440*itV;
		it_Time=(divValue/60);
		if (it_Time==0){
		    itTim=ithTime-1;
		}
		else{
		   itTim= it_Time-1;
		}
		return itTim;  
	}

    function _getCurrentIteration() internal view returns(uint current){
        uint ITT=_getIterationIndex();
        uint iTim;
        if (ITT==ithTime-1){
		    iTim=0;
		 }
		else{
		    iTim= ITT+1;
		 }
		 return iTim; 
    }

    /*This function is used to get the current time step*/
    function currentTimeStep() public view returns (uint step){
        uint timeStep=_getCurrentIteration();
        return timeStep;
    }


    /* Sorts sell and buy offers for all time steps	*/    
    function _initialSort(uint gridNu) internal {
		for (uint ith = 0; ith < ithTime; ith++){       
			_sortSellOffers(gridNu, ith);
			_sortBuyOffers(gridNu, ith);
		}
    }


    /*This function is use to determine the index of a unique value in an array*/
    function _getArrayIndex(address[] AddrArray, address uniqAddr) internal pure returns(uint indx){
        indx=0;
         for (uint i=0; i<AddrArray.length;i++){
            if(AddrArray[i]==uniqAddr){
                indx=i;  
            }
        } 
        return indx;
    }
}
