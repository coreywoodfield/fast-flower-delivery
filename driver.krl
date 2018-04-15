ruleset driver {

  meta {
    name "Driver"
    description <<Driver that delivers flowers>>
    use module gossip_node
    shares __testing
  }

  global {

    __testing = {
      "events": [
        {
          "domain": "driver",
          "type": "bid",
          "attrs": ["order_id"]
        },
        {
          "domain": "shop",
          "type": "bid_accepted",
          "attrs": ["order_id"]
        },
        {
          "domain": "driver",
          "type": "delivered",
          "attrs": [
            "order_id",
            "delivery_time"
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
    select when driver bid where isOwnerSubscribed(orderId))
    pre {
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
    select when driver bid where not(isOwnerSubscribed(orderId))
    pre {
      orderId = event:attr("orderId")
      shopId = shopFromOrder(orderId)
      message = getMessageByPossibleOrderId(orderId)
      host = message{"Host"}
      wellKnown_Tx = message{"WellKnown_Tx"}
      shopId = event:attr("shopId")
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
      shopId = event:attr("shopId")
      Tx = event:attr("Tx")
    }
    fired {
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