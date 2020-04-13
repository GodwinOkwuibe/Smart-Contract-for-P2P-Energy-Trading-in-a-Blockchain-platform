pragma solidity ^0.4.25;

import "./PeerEnergy.sol";

contract ExchangeContract{
    address ExchOwner;
    uint public tKStartTime = now;//should be negative 3 hours
    uint tokenMarktTime = 240 minutes;//Time to ckear Token Market (e.g is 4 hours)
    PeerEnergy interfcontract = PeerEnergy(0xf005a6696522f21698558917c1a15222eeeab315);
    
    modifier onlySmartMeter(address SMaddr) {
         require(interfcontract.checkSMNode(SMaddr) == true,
		 "Sender not authorised.");
         _;
     }
    
    constructor() public {
    	ExchOwner = msg.sender;
        }  
    
    modifier onlyOwner() {
    	require(msg.sender == ExchOwner, "Sender not authorised.");
        _;
    }
    
    /*  */
    function clearEnergy() public onlySmartMeter(msg.sender) {
        //should be 29 minutes 
        interfcontract.clearEnergyOrder(msg.sender);
    }
    
    
    /*  */
    function clearToken() public onlySmartMeter(msg.sender){
        if (now>=tKStartTime + tokenMarktTime){
        	interfcontract.clearTokenOffers();
        	tKStartTime += tokenMarktTime;
        }
        
    }
    
    
    /*  */
    function restartTrade() public onlyOwner() {
        interfcontract.restartTrade();
        tKStartTime = now;
    }
    
    
    //This function is use to change token market time in hours
    function changeTokenMarketTime(uint TimeInMins) public onlyOwner() {
        uint MarktTime = 60*TimeInMins;
        tokenMarktTime = MarktTime;
    }
}
