ruleset flower_shop {

  meta {
    name "Flower Shop"
    description <<Shop that sells flowers>>

    use module io.picolabs.subscription alias Subscriptions

    shares getLocation, __testing
  }

  global {

    __testing = {
      "queries": [
        { "name": "getLocation" }
      ],
      "events": [
        { "domain": "gossip", "type": "new_message", "attrs": [] }
      ]
    }

    drivers = function() {
      Subscriptions:established()
        .filter(function(sub) {
          sub{"Tx_role"} == "driver";
        });
    }
  
    getLocation = function() {
      ent:location
    }

    sequenceNumber = function() {
      ent:sequenceNum => ent:sequenceNum
                       | 0;
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
      raise shop event "initialized" attributes event:attrs
    }
  }

  // Automatically accept some subscriptions
  rule auto_accept_subscription {
    select when wrangler inbound_pending_subscription_added Rx_role re#^shop$#
    pre {
      attributes = event:attrs.klog("Subscription:")
    }
    fired {
      raise wrangler event "pending_subscription_approval" attributes attributes
    }
  }

  // Create a rumor message
  rule create_gossip_message {
    select when gossip new_message
    pre {
      sequenceNum = sequenceNumber()

      messageId = meta:picoId + ":" + sequenceNum
      sensorId = meta:txnId

      msg = {
        "MessageId": messageId,
        "ShopId": meta:picoId,
        "Timestamp": time:now()
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

}
