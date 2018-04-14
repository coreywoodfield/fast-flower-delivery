// Twilio API wrapper module

ruleset twilio {
  meta {
    name "Twilio Module"
    description <<
Module for using the Twilio API
>>
    author "Curtis Oakley"

    logging on

    configure using account_sid = ""
                    auth_token = ""

    provides
        send_sms,
        messages
  }

  global {
    base_url = <<https://api.twilio.com/2010-04-01/Accounts/#{account_sid}/>>

    send_sms = defaction(to, from, message) {
      http:post(
        base_url + "Messages.json",
        auth = {
          "user": account_sid,
          "password": auth_token
        },
        form = {
          "From": from,
          "To": to,
          "Body": message
        },
        autoraise = "twilio"
      )
    }

    messages = function(page = 0, pageSize = 50, sendingNum = "", receivingNum = "") {
      page = (page == "") => 0 | page;
      pageSize = (pageSize == "") => 50 | pageSize;
      params = {
        "Page": page,
        "PageSize": pageSize
      };
      params = (sendingNum == "") => params | params.put({ "From": sendingNum });
      params = (receivingNum == "") => params | params.put({ "To": receivingNum });

      response = http:get(
        base_url + "Messages.json",
        qs = params,
        auth = {
          "user": account_sid,
          "password": auth_token
        }
      );

      // Extract the response content from the GET request
      // Modified from: https://picolabs.atlassian.net/wiki/spaces/docs/pages/1184812/Calling+a+Module+Function+in+Another+Pico
      status = response{"status_code"};

      error_info = {
        "error": "messages request was unsuccesful.",
        "httpStatus": {
          "code": status,
          "message": response{"status_line"}
        }
      };

      response_content = response{"content"}.decode();
      response_error = (response_content.typeof() == "Map" && response_content{"error"}) => response_content{"error"} | 0;
      response_error_str = (response_content.typeof() == "Map" && response_content{"error_str"}) => response_content{"error_str"} | 0;
      error = error_info.put({"responseError": response_error, "responseErrorStr": response_error_str, "response": response_content});
      is_bad_response = (response_content.isnull() || response_content == "null" || response_error || response_error_str);

      // if HTTP status was OK & the response was not null and there were no errors...
      (status == 200 && not is_bad_response) => response_content | error
    }
  }

  rule twilioResponse {
    select when http post label re#twilio#
    fired {
      log debug <<Twilio HTTP POST Response:
Status:  #{event:attr("status_code")} #{event:attr("status_line")}
Headers: #{event:attr("headers").encode()}
Content: #{event:attr("content")}>>
    }
  }
}

