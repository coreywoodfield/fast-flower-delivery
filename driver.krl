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
          "domain": "flowers",
          "type": "offer",
          "attrs": [
            "shop",
            "host",
            "wellKnown_Tx",
            "amount",
            "store_location",
            "destination"
          ]
        },
        {
          "domain": "flowers",
          "type": "bid_accepted",
          "attrs": [
            "destination",
            "amount",
            "expected_delivery_time",
            "uuid",
            "shop"
          ]
        },
        {
          "domain": "flowers",
          "type": "delivered",
          "attrs": [
            "destination",
            "expected_delivery_time",
            "uuid",
            "shop"
          ]
        }
      ]
    }

    location = function() {

    }

    ranking = function() {

    }

    orders = function() {

    }

    connections = function() {

    }

  }

  rule bid {
    select when flowers offer

  }

  rule store_delivery_info {
    select when flowers bid_accepted

  }

  rule report_delivered {
    select when flowers delivered

  }

}