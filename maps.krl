ruleset google_maps {
  meta {
    use module keys
    provides get_time, get_random_location
    shares get_time
  }

  global {
    base_url = "https://maps.googleapis.com/maps/api/distancematrix/json"

    // get the projected travel time between a shop and a driver
    get_time = function(shop, driver) {
      shop = shop.decode();
      driver = driver.decode();
      http:get(
        base_url,
        qs = {
          "key": keys:google_maps{"api_key"},
          "units": "imperial",
          "origins": <<#{driver{"lat"}},#{driver{"long"}}>>,
          "destinations": <<#{shop{"lat"}},#{shop{"long"}}>>
        },
        parseJSON = true
      ){["content","rows"]}[0]{"elements"}[0]{["duration","value"]}
    }

    // get lat/long associated with a random location in utah
    // 41.9927959,-114.0408359 -> NE Corner
    // 36.9990868,-109.0474112 -> SW corner
    get_random_location = function() {
      latitude = random:number(36.9990868, 41.9927959);
      longitude = random:number(-114.0408359, -109.0474112);
      {"lat": latitude, "long": longitude}
    }
  }
}
