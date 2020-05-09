pragma solidity ^0.4.25;

import "./ERC20.sol";

contract DoubleSidedAuction is ERC20 {
    /*Declaration of variables*/
    /*The struct below creates users to participate in peer energy trading*/
    struct User {
        uint typeOfUser; //1 for consumer 2 for prosumer, 3 for generator
		uint gridNo; //grid number of the user
        uint consumedEnergy;//Energy consumed by the user
        uint producedEnergy;//Energy produced
        uint time;//summed time before balancing grid 
        uint[] BQty;// quatity of energy bought from market
        uint[][] SQty;// quantity of energy sold which it suppose to produce
        uint[][] SPrice;//price of each quatity sold
        uint []sellcount;//used to count number of participants it has satified with energy produced
        uint userDebt;
        uint RelayState;
        uint UtilityDebt;
    }

    /*This struct variables will be used to recieve all matched bids and ask 
    Avgprice: Average price after the bids and ask was matched
    AvgQty: average quantity of matched bids
    Seller: user address of the Seller
    Buyer: user address of the Buyer
    RfId: reference number of the bids
    countconfirm: used to confirm match payment*/
    //address useraddr;
    struct MergedAskBid {
        uint AvgPrice;
        uint AvgQty;
        address Seller;
        address Buyer;
        uint RfId;
        uint countconfirm;
    }

    User[] public users;
    //modifiers and their functions

    /* This modifier is use for functions that only the smart meter can call*/
    modifier OnlySmartMeter(address _addr){
        require(_addr==userIDtoAddress[userAddresstoID[_addr]],"Not Smart Meter");
        _;
    }

    /* This modifier is use for functions that only the user Application phone can call
    can call*/
    modifier OnlyAppNode (address _addrr){
        require(AppToSmartmeter[_addrr]== userIDtoAddress[userAddresstoID[AppToSmartmeter[_addrr]]],
        "Not Application Node");
        _;
    }

    /* This modifier is use for functions that only the Generator Application phone can call
    can call*/
    modifier OnlyUtility(address _UtilityAddr){
        require(_UtilityAddr==Utility,
        "Not Generator Application Node");
        _;
    }

    //This is use to give restrictions on the token a user can bid
    modifier AskTkrequirements (uint _qty){
        require(balanceOf[AppToSmartmeter[msg.sender]] >= _qty + MinBal,
        "Not Enough balance");
        _;
    }
    /*Below is array variables for sell price, sell quatity and addres of user*/
    /*Abbreviation was chosen for the six variable below because they were used in many places
    Hence the need to reduce code length*/
    uint[] Sp;//Sell price
    uint[] Sq;//Sell quantity
    address[] SAddr;//Seller adress

    /*Below is the variable declaration for buy price, buy quantity and buyer addresse*/
    uint[] Bp;//Buy price
    uint[] Bq;//Buy quantity
    address[] BAddr; // Buyer address
    uint r1;//This is used to count how many transactions was done after each matching

    uint public MinBal =500; //minimum balance a user need to leave in the account while selling token

    MergedAskBid[] public ArrayWonBid;

    mapping (uint => uint) public RefId;//reference id for each of matched bid
    mapping (uint => uint) internal RefIndex;// index used to call values in ArrayWonBid

    mapping (uint => address) public userIDtoAddress; 	// This is used to map the user's ID to the user's address throughout the entire network
    mapping (address => uint) public userAddresstoID; 	// This is used to map the user's address to his ID throughout the entire network (NOT the ID within the microgrid)


    /* Changes the minimum balance required before each user can sell token*/
    function changeMinBalance(uint _Min) public onlyOwner()  {
        MinBal = _Min;  
    } 


    /*This function is used to bid to sell token
    _price: sell price per token
    _Qty: quantity to sell
    This function basically pushes the bid into the required arrays and sort them*/
    function placeSellTokenOffer(uint _price, uint _Qty) public OnlyAppNode (msg.sender) AskTkrequirements (_Qty){  
        approve(ExchangeAddr, _Qty);
        Sp.push(_price);
        Sq.push(_Qty);
        SAddr.push(msg.sender);
        (Sp,Sq, SAddr) = _sortSellPrices(Sp,Sq, SAddr);
    }


    /*This function is used to bid to buy token
    _price: buy price per token
    _Qty: quantity to buy
    This function basically pushes the ask into the required arrays and sort them*/
    function placeBuyTokenOffer(uint _price, uint _Qty) public  OnlyAppNode (msg.sender) {  
        Bp.push(_price);
        Bq.push(_Qty);
        BAddr.push(msg.sender);
        (Bp,Bq, BAddr) = _sortBuyPrices(Bp,Bq, BAddr);

        return;
    }


    /*This function is used to view the bid*/
    function viewSellTokenOffers() public view returns (uint [] Sell_Price, uint [] Sell_Qty) {
        return (Sp, Sq); 
    }


    /*This function is used to view ask*/
    function viewBuyTokenOffers() public view returns (uint [] Buy_Price, uint [] Buy_Qty) {
        return (Bp, Bq); 
    }


    /*This function is used to sort the given arrays with the least price as the index zero
    till the highest price*/
    function _sortSellPrices(uint[] Arr_, uint[] qty_, address[]  _sAddr) internal pure 
        returns (uint [], uint [], address[]) {
        uint256 l = Arr_.length;
        uint[] memory Listsell = new uint[] (l);
        uint[] memory Listqty = new uint[] (l);
        address[] memory sAddr = new address[] (l);  
        for(uint i=0; i<l; i++){
            Listsell[i] = Arr_[i];
            Listqty[i] = qty_[i];
            sAddr[i] = _sAddr[i];
        }
        for(uint k=0; k<l; k++){
            for (uint j=k+1; j<l; j++){
                if (Listsell[k]>Listsell[j]){
                    uint temp = Listsell[j];
                    Listsell[j] = Listsell[k];
                    Listsell[k] = temp;
                    uint tempq = Listqty[j];
                    Listqty[j] = Listqty[k];
                    Listqty[k] = tempq;
                    address tempad = sAddr[j];
                    sAddr[j] = sAddr[k];
                    sAddr[k] = tempad;
                }
            }  
        }
        return (Listsell, Listqty, sAddr); 
    }


    /*This function is used to sort the given arrays with the highest price as the index zero
    till the lowest price*/
    function _sortBuyPrices(uint[] Arr_, uint[] qty_, address[] _bAddr) internal pure 
        returns (uint [], uint [], address[]) {
        uint256 l = Arr_.length;
        uint[] memory ListbuyP = new uint[] (l);
        uint[] memory ListbuyQ = new uint[] (l);
        address[] memory bAddr = new address[] (l);  
        for(uint i=0; i<l; i++){
            ListbuyP[i] = Arr_[i];
            ListbuyQ[i] = qty_[i];
            bAddr[i] = _bAddr[i];
        }
        for(uint k=0; k<l; k++){
            for (uint j=k+1; j<l; j++){
                if (ListbuyP[k]<ListbuyP[j]){
                    uint temp = ListbuyP[j];
                    ListbuyP[j] = ListbuyP[k];
                    ListbuyP[k] = temp;
                    uint tempq = ListbuyQ[j];
                    ListbuyQ[j] = ListbuyQ[k];
                    ListbuyQ[k] = tempq;
                    address tempas = bAddr[j];
                    bAddr[j] = bAddr[k];
                    bAddr[k] = tempas;
                }
            }  
        }
        return (ListbuyP, ListbuyQ, bAddr);
    }


    //This is used to call the function MatchBidAsk to match all bids and ask
    function clearTokenOffers() public onlyAlarm() {   //To be called by ethereum alarm clock
        _matchBuyAndSellOffers();
    }   


    /*This function is used Transfer token from seller to owner after the matching
    The token remains in the account of the owner till both participants confirms recipient
    and tranfer of fiered currency*/
    function _assignMatchedPrices( uint _Avp, uint _Avq) internal returns (uint){
        uint RefDigits = 22;uint ref;uint _id;
        uint RefModulus = 10 ** RefDigits; 
        ref = uint(keccak256(abi.encodePacked(SAddr[0],BAddr[0],now,r1)));
        if (balanceOf[AppToSmartmeter[SAddr[0]]]>=_Avq){
	        ERC20.transferFrom(AppToSmartmeter[SAddr[0]], ExchangeAddr, _Avq);
            ERC20.allowance[ExchangeAddr][BAddr[0]] += _Avq;
            ERC20.allowance[ExchangeAddr][SAddr[0]] += _Avq; 
            ref = ref % RefModulus;
		    _id= ArrayWonBid.push(MergedAskBid(_Avp, _Avq,SAddr[0],BAddr[0],ref, 0 ))-1;
		    RefId[_id] = ref;
	        RefIndex[ref]=_id;
			return 2;
		}
		else{
		    return 1;
		}
    }


    /*This function matches the bids and asks from the list index till the 
    price do not conform to market agreement(sell price<=buyer price)*/
    function _matchBuyAndSellOffers() internal  {
        uint df;
        uint8 y=1;//used to know end of while loop
        uint Avp;//average price
        uint Avq;//average quatity
        r1 =1;
        while(y>0 && Sp.length>0 && Bp.length>0){
	        uint i;   uint index =0;
	        if(Sp[0]<= Bp[0]) {
	            if (Sq[0] == Bq[0]){
		            Avp = (Sp[0]+Bp[0])/2;
		            Avq= Sq[0];
		            if (_assignMatchedPrices( Avp, Avq)==2){
                        for (i = index; i<Bq.length-1; i++){
                            Bq[i] = Bq[i+1];
                            Bp[i] = Bp[i+1];
                            BAddr[i] = BAddr[i+1];
                        }
                        Bq.length--; Bp.length--; BAddr.length--;r1++;
					}  
	                for (i = index; i<Sq.length-1; i++){
                        Sq[i] = Sq[i+1];
                        Sp[i] = Sp[i+1];
                        SAddr[i] = SAddr[i+1];
                    }			
                    Sq.length--; Sp.length--; SAddr.length--;
                }
		        else if (Sq[0] > Bq[0]){
		            df= Sq[0] - Bq[0];
	                Avp = (Sp[0]+Bp[0])/2;
		            Avq= Bq[0];
                    if (_assignMatchedPrices( Avp, Avq)==2){
		                for ( i = index; i<Bq.length-1; i++){
                            Bq[i] = Bq[i+1];
                            Bp[i] = Bp[i+1];
                            BAddr[i] = BAddr[i+1];
                        }
					    Bq.length--; Bp.length--; BAddr.length--; r1++;
                    }
					Sq[0]= df; 
                }
		        // comment
	            else{
		            df= Bq[0] - Sq[0];
	        	    Avp = (Sp[0]+Bp[0])/2;
		            Avq= Sq[0];
		            if (_assignMatchedPrices( Avp, Avq)==2){
	            	    Bq[0]= df; 
					}
	            	for (i = index; i<Sq.length-1; i++){
                        Sq[i] = Sq[i+1];
                        Sp[i] = Sp[i+1];
                        SAddr[i] = SAddr[i+1];
                    }
	                Sq.length--; Sp.length--; SAddr.length--;r1++;
		        }
        	}
        	else{
            	y=0;
        	}
        }
    }


    /*This function is used by seller to confirm recipient of fiered currency*/
    function sellerConfirmation(uint _RefId) public OnlyAppNode (msg.sender)  returns(bool success) {
        if(ArrayWonBid[RefIndex[_RefId]].Seller == msg.sender){
            if (ArrayWonBid[RefIndex[_RefId]].countconfirm ==1){
                transferFrom(ExchangeAddr, 
                            AppToSmartmeter[ArrayWonBid[RefIndex[_RefId]].Buyer],
                            ArrayWonBid[RefIndex[_RefId]].AvgQty);
                ERC20.allowance[ExchangeAddr][ArrayWonBid[RefIndex[_RefId]].Buyer] -= 
                ArrayWonBid[RefIndex[_RefId]].AvgQty;
                ArrayWonBid[RefIndex[_RefId]].countconfirm =3;
                return true; 
            }
            else if(ArrayWonBid[RefIndex[_RefId]].countconfirm ==0) {
               ArrayWonBid[RefIndex[_RefId]].countconfirm =2;
               return true;
            }
            else{
               return false;
            }
        }
        else {
            return false;
        }
    }


    /*This function is used by buyer to confirm transfer of fiered currency*/
    function buyerConfirmation(uint _RefId) public OnlyAppNode (msg.sender) returns(bool success){
        if (ArrayWonBid[RefIndex[_RefId]].Buyer == msg.sender){
            if (ArrayWonBid[RefIndex[_RefId]].countconfirm ==2){
                transferFrom(ExchangeAddr, 
                            AppToSmartmeter[ArrayWonBid[RefIndex[_RefId]].Buyer],
                            ArrayWonBid[RefIndex[_RefId]].AvgQty);
                ERC20.allowance[ExchangeAddr][ArrayWonBid[RefIndex[_RefId]].Seller] -= 
                ArrayWonBid[RefIndex[_RefId]].AvgQty;
                ArrayWonBid[RefIndex[_RefId]].countconfirm =3;  
                return true;
           }
           else if(ArrayWonBid[RefIndex[_RefId]].countconfirm ==0) {
                ArrayWonBid[RefIndex[_RefId]].countconfirm =1;
                return true;
           }
           else{
               return false;
           }
        }
        else {
            return false;
        }
    }
}
