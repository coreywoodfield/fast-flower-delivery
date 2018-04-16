ruleset driver {

  meta {
    name "Driver"
    description <<Driver that delivers flowers>>
    use module gossip_node
    use module io.picolabs.wrangler alias wrangler
    use module io.picolabs.subscription alias Subscriptions
    shares location, __testing
  }

  global {

    __testing = {
      "events": [
        {
          "domain": "driver",
          "type": "bid",
          "attrs": ["orderId"]
        },
        {
          "domain": "shop",
          "type": "bid_accepted",
          "attrs": ["orderId"]
        },
        {
          "domain": "driver",
          "type": "delivered",
          "attrs": [
            "orderId",
            "deliveryTime"
          ]
        }
      ]
    }

    location = function() {
      {
        "lat": "40.256984",
        "long": "-111.649206"
      }
    }

    ranking = function() {
      ent:ranking.defaultsTo(5)
    }

    orders = function() {
      ent:orders.defaultsTo({})
    }

    unclaimed = function() {
      gossip_node:getMessages().filter(function(x) {
        not(x{"Claimed"})
      })
    }

    getMessageByPossibleOrderId = function(orderId) {
      gossip_node:getMessages().filter(function(x) {
        x{"Order"}{"id"} == orderId
      })[0]
    }

    isOwnerSubscribed = function(orderId) {
      isSubscribed(
        shopFromOrder(orderId)
      )
    }

    shopFromOrder = function(orderId) {
      getMessageByPossibleOrderId(orderId){"ShopId"}
    }

    isSubscribed = function(shopId) {
      ent:id_to_Tx.defaultsTo({}).keys() >< shopId
    }

  }

  rule bid {
    select when driver bid where isOwnerSubscribed(orderId)
    pre {
      orderId = event:attr("orderId")
      message = getMessageByPossibleOrderId(orderId)
      shopId = message{"ShopId"}
      Tx = ent:id_to_Tx{shopId}
      Rx = Subscriptions:established("Tx", Tx)[0]{"Rx"}
      attrs = event:attrs.put({
        "driverId": meta:picoId,
        "Tx": Rx,
        "ranking": ranking(),
        "location": location()
      })
    }
    event:send({
      "eci": Tx,
      "eid": "driver_bid",
      "domain": "driver",
      "type": "bid",
      "attrs": attrs
    })
  }

  rule subscribe_to_shop {
    select when driver bid where not isOwnerSubscribed(orderId)
    pre {
      orderId = event:attr("orderId")
      shopId = shopFromOrder(orderId)
      message = getMessageByPossibleOrderId(orderId)
      Rx_host = meta:host
      Tx_host = message{"Host"}
      wellKnown_Rx = Subscriptions:wellKnown_Rx(){"id"}
      wellKnown_Tx = message{"WellKnown_Tx"}
    }
    event:send({
      "eci": wellKnown_Tx,
      "eid": "driver_subscribe",
      "host": Tx_host,
      "domain": "wrangler",
      "type": "subscription",
      "attrs": {
        "channel_type": "subscription",
        "Tx_host": Rx_host,
        "wellKnown_Tx": wellKnown_Rx,
        "Rx_role": "shop",
        "Tx_role": "driver",
        "orderId": orderId
      }
    })
  }

  rule bid_on_id_to_Tx_stored {
    select when driver id_to_Tx_stored where orderId
    fired {
      raise driver event "bid"
        attributes {"orderId": event:attr("orderId")}
    }
  }

  rule store_id_to_Tx {
    select when wrangler pending_subscription_approval
    pre {
      Tx = event:attr("Tx")
      shopId = wrangler:skyQuery(Tx, "flower_shop", "id", {})
    }
    fired {
      ent:id_to_Tx := id_to_Tx.defaultsTo({});
      ent:id_to_Tx{shopId} := Tx;
      raise driver event "id_to_Tx_stored"
        attributes {"orderId": event:attr("orderId")}
    }
  }

  rule store_delivery_info {
    select when shop bid_accepted

  }

  rule report_delivered {
    select when driver delivered

  }

}