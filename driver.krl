ruleset driver {

  meta {
    name "Driver"
    description <<Driver that delivers flowers>>
    use module gossip_node
    use module io.picolabs.wrangler alias wrangler
    shares __testing
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
        shopFromOrder(orderId).klog("SFO")
      ).klog("IS SUBSCRIBED")
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
      a = null.klog("YES SUBSCRIBED")
      orderId = event:attr("orderId")
      shopId = message{"ShopId"}
      Tx = ent:id_to_Tx(shopId)
    }
    send({
      "eci": Tx,
      "eid": "driver_bid",
      "domain": "driver",
      "type": "bid",
      "attrs": event:attrs
    })
  }

  rule subscribe_to_shop {
    select when driver bid where not isOwnerSubscribed(orderId).klog("IS_SUBSCRIBED")
    pre {
      a = null.klog("NOT SUBSCRIBED")
      orderId = event:attr("orderId")
      shopId = shopFromOrder(orderId)
      message = getMessageByPossibleOrderId(orderId)
      host = message{"Host"}
      wellKnown_Tx = message{"WellKnown_Tx"}
    }
    event:send({
      "eci": wellKnown_Tx,
      "eid": "driver_subscribe",
      "domain": "wrangler",
      "type": "subscription",
      "attrs": {
        "channel_type": "subscription",
        "Tx_host": host,
        "wellKnown_Tx": wellKnown_Tx,
        "Rx_role": "driver",
        "Tx_role": "shop",
        "shopId": shopId,
        "orderId": orderId
      }
    })
  }

  rule bid_on_subscription {
    select when wrangler pending_subscription_approval where orderId
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
      ent:id_to_Tx{shopId} := Tx
    }
  }

  rule store_delivery_info {
    select when shop bid_accepted

  }

  rule report_delivered {
    select when driver delivered

  }

}