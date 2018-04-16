Title: Fluber


Shop -> Drivers: order_created

Note: 
Order information is sent to all drivers the shop knows.


Drivers <-> Driver: Gossip

Note:
Drivers propagate order information via a gossip protocol.

Driver -> Shop: bid
Driver -> Shop: bid

Note:
Drivers may send back a bid.

Shop -> Google Maps: distance

Note:
The shop priortizes bids based on distance information from Google Maps.

Shop -> Driver: bid_accepted

Note:
The shop sends the accepted bid to the driver.

Shop -> Twilio: sms

Note:
The shop sends an SMS message to the customer via Twilio

Driver -> Shop: order_delivered

Note:
Driver lets the shop know the order was fullfilled and delivered.
