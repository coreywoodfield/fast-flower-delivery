ruleset flower_shop {

  meta {
    name "Flower Shop"
    description <<Shop that sells flowers>>

    use module io.picolabs.subscription alias Subscriptions
    use module google_maps

    shares getLocation, id, __testing
  }

  global {

    __testing = {
      "queries": [
        { "name": "getLocation" }
      ],
      "events": [
        { "domain": "gossip", "type": "new_message", "attrs": [] },
        { "domain": "shop", "type": "driver_requested", "attrs": ["destination", "customerPhone"] }
      ]
    }

    drivers = function() {
      Subscriptions:established()
        .filter(function(sub) {
          sub{"Tx_role"} == "driver"
        });
    }
  
    getLocation = function() {
      ent:location
    }

    sequenceNumber = function() {
      ent:sequenceNum => ent:sequenceNum
                       | 0;
    }

    id = function() {
      meta:picoId
    }

  }

  rule initialize {
    select when wrangler ruleset_added where rid == meta:rid
    // Randomly assign a location to this flower shop
    pre {
      // Generate a random latitude and longitude in Utah
      // 41.9927959,-114.0408359 -> NE Corner
      // 36.9990868,-109.0474112 -> SW corner
      latitude = random:number(41.9, 36.9)
      longitude = random:number(-114.0, -109.0)
      
      location = {
        "lat": latitude,
        "long": longitude
      }
    }
    fired {
      ent:location := location;
      ent:bids := {};
      raise shop event "initialized" attributes event:attrs
    }
  }

  // Automatically accept some subscriptions
  rule auto_accept_subscription {
    select when wrangler inbound_pending_subscription_added Rx_role re#^shop$#
    fired {
      raise wrangler event "pending_subscription_approval" attributes event:attrs
    }
  }

  rule request_driver {
    select when shop driver_requested
    pre {
      orderId = random:uuid()
      order = {
        "id": orderId,
        "shop": meta:picoId,
        "destination": event:attr("destination"),
        "customerPhone": event:attr("customerPhone")
      }
    }
    send_directive("created order", order)
    fired {
      raise gossip event "new_message"
        attributes {
          "order": order
        };
      ent:orders := ent:orders.defaultsTo({}).put(orderId, order)
    }
  }

  rule store_bid {
    select when driver bid
    fired {
      event:attrs.klog("Bid Attributes:")
    }
  }

  // Create a rumor message
  rule create_gossip_message {
    select when gossip new_message
    pre {
      sequenceNum = sequenceNumber()

      messageId = meta:picoId + ":" + sequenceNum

      msg = {
        "MessageId": messageId,
        "ShopId": meta:picoId,
        "Timestamp": time:now(),
        "Host": meta:host,
        "WellKnown_Tx": Subscriptions:wellKnown_Rx(){"id"},
        "Claimed": false,
        "Order": event:attr("order")
        // Additonal items to send out for gossiping
      }
    }
    send_directive("Created new gossip message", msg)
    fired {
      // Increment the sequence number
      ent:sequenceNum := sequenceNum + 1;

      // Trigger an event to send the message to all known drivers
      raise gossip event "broadcast" attributes msg
    }
  }

  // Send a rumor message to all drivers
  rule broadcast_gossip_message {
    select when gossip broadcast
    foreach drivers() setting(driver)
      pre {
        host = driver{"Tx_host"} => driver{"Tx_host"}
                                  | meta:host
        e = {
          "eci": driver{"Tx"},
          "eid": meta:picoId + "_gossip_msg",
          "domain": "gossip",
          "type": "rumor",
          "attrs": event:attrs
        }
      }
      event:send(e, host=host)
      always {
        raise gossip event "msg_broadcast" attributes event:attrs on final
      }
    // End foreach
  }

  // schedule event to process the bids on a delivery
  rule message_sent {
    select when gossip msg_broadcast
    pre {
      id = event:attr("MessageId")
    }
    always {
      ent:bids := ent:bids.put(id, []);
      schedule shop event "process_bids" at time:add(time:now(), {"seconds": ent:wait_time }) attributes {"MessageId": id}
    }
  }

  rule process_bids {
    select when event process_bids
    pre {
      loc = ent:location;
      bids = ent:bids{event:attr("MessageId")};
      bids = bids.map(function(bid) {
        bid.put("travel_time", google_maps(loc, bid{"location"}))
      });
      winner = bids.reduce(function(bid1, bid2) {
        rating1 = bid1{"rating"};
        time1 = bid1{"travel_time"};
        // better rating means they can get it from further away
        // score is like golf - the lower the better
        score1 = time1 - (rating1 * 60);
        rating2 = bid2{"rating"};
        time2 = bid2{"travel_time"};
        score2 = time2 - (rating2 * 60);
        (score1 <= score2) => bid1 | bid2
      });
      eci = winner{"eci"}
    }
    event:send({
      "eci": eci,
      "domain": "driver",
      "type": "bid_selected",
      "attrs": event:attrs,
      "host": bid{"host"}
    })
  }

}
