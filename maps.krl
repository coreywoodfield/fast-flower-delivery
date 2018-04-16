ruleset google_maps {
  meta {
    use module keys
    provides get_time
    shares get_time
  }

  global {
    base_url = "https://maps.googleapis.com/maps/api/distancematrix/json"

    get_time = function(shop, driver) {
      shop = shop.decode();
      driver = driver.decode();
      http:get(
        base_url,
        qs = {
          "key": keys:google_maps{"api_key"},
          "units": "imperial",
          "origins": <<#{driver{"latitude"}},#{driver{"longitude"}}>>,
          "destinations": <<#{shop{"latitude"}},#{shop{"longitude"}}>>
        },
        parseJSON = true
      ){["content","rows"]}[0]{"elements"}[0]{["duration","value"]}
    }
  }
}
