ruleset driver {

  meta {
    name "Driver"
    description <<Driver that delivers flowers>>
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

  }

  rule bid {
    select when driver bid

  }

  rule store_delivery_info {
    select when shop bid_accepted

  }

  rule report_delivered {
    select when driver delivered

  }

}