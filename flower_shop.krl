ruleset flower_shop {

  meta {
    name "Flower Shop"
    description <<Shop that sells flowers>>

    use module io.picolabs.subscription alias Subscriptions
    use module google_maps
    use module twilio
        with account_sid = keys:twilio{"sid"}
             auth_token = keys:twilio{"token"}

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
      location = google_maps:get_random_location()
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

  rule create_order {
    select when shop order
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
      raise shop event "order_created"
        attributes {
          "order": order
        };
      ent:orders := ent:orders.defaultsTo({}).put(orderId, order)
    }
  }

  rule request_driver {
    select when shop order_created
    pre {
	  // Create a gossip message for the order
      msg = {
        "Claimed": false,
        "Host": meta:host,
        "WellKnown_Tx": Subscriptions:wellKnown_Rx(){"id"},
        "ShopId": meta:picoId,
        "Order": event:attrs{"order"}
      }
    }
    fired {
      raise gossip event "new_message"
        attributes {
          "msg": msg
        }
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

      msg = event:attrs{"msg"}
        .put("MessageId", messageId)
        .put("Timestamp", time:now()).klog("Gossip Message:")
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
    select when shop order_created
    pre {
      id = event:attrs{["Order","id"]}
    }
    always {
      ent:bids := ent:bids.put(id, []);
      schedule shop event "process_bids" at time:add(time:now(), {"seconds": ent:wait_time }) attributes event:attr("Order")
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
        rating1 = bid1{"ranking"};
        time1 = bid1{"travel_time"};
        // better rating means they can get it from further away
        // score is like golf - the lower the better
        score1 = time1 - (rating1 * 60);
        rating2 = bid2{"ranking"};
        time2 = bid2{"travel_time"};
        score2 = time2 - (rating2 * 60);
        (score1 <= score2) => bid1 | bid2
      });
      eci = winner{"Tx"}
    }
    event:send({
      "eci": eci,
      "domain": "shop",
      "type": "bid_accepted",
      "attrs": event:attrs,
      "host": bid{"host"}
    })
    always {
      raise shop event bid_accepted attributes event:attrs
    }
  }

  rule notify_customer {
    select when shop bid_accepted
    twilio:send_sms(event:attr("customerPhone"), "+13854744122", "Your flowers will be delivered soon!")
  }

}
