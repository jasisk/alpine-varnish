vcl 4.0;

import std;
import bodyaccess;

acl purge {
  "localhost";
  "127.0.0.1";
}

sub vcl_recv {
  set req.http.host = std.tolower(req.http.host);

  # loloops. https://httpoxy.org/#mitigate-varnish
  unset req.http.proxy; 

  # I use this later--good practice to clear out used headers
  unset req.http.x-len; 

  # normalize qs
  set req.url = std.querysort(req.url); 

  # allow PURGE but only from clients according to the acl
  if (req.method == "PURGE") {
    if (!client.ip ~ purge) {
      return (synth(405, "This IP is not authorized to send PURGE requests."));  
    }
    return (purge);
  }

  if (req.method != "GET" &&
      req.method != "HEAD" &&
      req.method != "PUT" &&
      req.method != "POST" &&
      req.method != "TRACE" &&
      req.method != "OPTIONS" &&
      req.method != "PATCH" &&
      req.method != "DELETE") {
    return(synth(404, "Invalid HTTP method."));
  }

  # PASS non-GETs and HEADs
  if (req.method != "GET" && req.method != "HEAD") {
    return (pass);
  }

  # strip hash
  if (req.url ~ "\#") {
    set req.url = regsub(req.url, "\#.*$", "");
  }

  # strip trailing question marks
  if (req.url ~ "\?$") {
    set req.url = regsub(req.url, "\?$", "");
  }

  ##### a bunch of shit I found online for GA etc #####
  if (req.url ~ "(\?|&)(utm_source|utm_medium|utm_campaign|utm_content|gclid|cx|ie|cof|siteurl)=") {
    set req.url = regsuball(req.url, "&(utm_source|utm_medium|utm_campaign|utm_content|gclid|cx|ie|cof|siteurl)=([A-z0-9_\-\.%25]+)", "");
    set req.url = regsuball(req.url, "\?(utm_source|utm_medium|utm_campaign|utm_content|gclid|cx|ie|cof|siteurl)=([A-z0-9_\-\.%25]+)", "?");
    set req.url = regsub(req.url, "\?&", "?");
    set req.url = regsub(req.url, "\?$", "");
  }

  # Some generic cookie manipulation, useful for all templates that follow
  # Remove the "has_js" cookie
  set req.http.Cookie = regsuball(req.http.Cookie, "has_js=[^;]+(; )?", "");

  # Remove any Google Analytics based cookies
  set req.http.Cookie = regsuball(req.http.Cookie, "__utm.=[^;]+(; )?", "");
  set req.http.Cookie = regsuball(req.http.Cookie, "_ga=[^;]+(; )?", "");
  set req.http.Cookie = regsuball(req.http.Cookie, "_gat=[^;]+(; )?", "");
  set req.http.Cookie = regsuball(req.http.Cookie, "utmctr=[^;]+(; )?", "");
  set req.http.Cookie = regsuball(req.http.Cookie, "utmcmd.=[^;]+(; )?", "");
  set req.http.Cookie = regsuball(req.http.Cookie, "utmccn.=[^;]+(; )?", "");

  # Remove DoubleClick offensive cookies
  set req.http.Cookie = regsuball(req.http.Cookie, "__gads=[^;]+(; )?", "");

  # Remove the Quant Capital cookies (added by some plugin, all __qca)
  set req.http.Cookie = regsuball(req.http.Cookie, "__qc.=[^;]+(; )?", "");

  # Remove the AddThis cookies
  set req.http.Cookie = regsuball(req.http.Cookie, "__atuv.=[^;]+(; )?", "");

  # Remove a ";" prefix in the cookie if present
  set req.http.Cookie = regsuball(req.http.Cookie, "^;\s*", "");

  # Are there cookies left with only spaces or that are empty?
  if (req.http.cookie ~ "^\s*$") {
    unset req.http.cookie;
  }

  ##### end of shit I found online #####

  if (req.url ~ "^[^?]*\.(7z|avi|bmp|bz2|css|csv|doc|docx|eot|flac|flv|gif|gz|ico|jpeg|jpg|js|less|mka|mkv|mov|mp3|mp4|mpeg|mpg|odt|otf|ogg|ogm|opus|pdf|png|ppt|pptx|rar|rtf|svg|svgz|swf|tar|tbz|tgz|ttf|txt|txz|wav|webm|webp|woff|woff2|xls|xlsx|xml|xz|zip)(\?.*)?$") {
    unset req.http.Cookie;
    return (hash);
  }

  if (req.http.Authorization || req.http.Cookie) {
		return (pass);
	}

  # noop but leaving in here for future use
  if (req.method == "POST") {
    std.cache_req_body(10KB);
    set req.http.x-len = bodyaccess.len_req_body();

    if (req.http.x-len == "-1") {
      return (synth(400, "Bad request"));  
    }

    return (hash);
  }

  # CACHE WOOOOOO
	return (hash);
}

sub vcl_hash {
  # no explicit call to return(lookup) so host + url already considered

  if (req.http.Cookie) {
    hash_data(req.http.Cookie);
  }

  if (req.http.x-len) {
    bodyaccess.hash_req_body();   
  }
}

sub vcl_hit {
  if (obj.ttl >= 0s) {
    return (deliver);  
  }
  if (obj.ttl + obj.grace > 0s) {
    return (deliver);  
  }
  return (fetch);
}

sub vcl_backend_response {
  if (bereq.url ~ "^[^?]*\.(7z|avi|bmp|bz2|css|csv|doc|docx|eot|flac|flv|gif|gz|ico|jpeg|jpg|js|less|mka|mkv|mov|mp3|mp4|mpeg|mpg|odt|otf|ogg|ogm|opus|pdf|png|ppt|pptx|rar|rtf|svg|svgz|swf|tar|tbz|tgz|ttf|txt|txz|wav|webm|webp|woff|woff2|xls|xlsx|xml|xz|zip)(\?.*)?$") {
    unset beresp.http.cache-control;  
    unset beresp.http.set-cookie;  
    set beresp.ttl = 5m;
  }

  # this asset is uncachable.
  if (beresp.ttl <= 0s || beresp.http.Set-Cookie || beresp.http.Vary == "*") {
    set beresp.ttl = 120s;
    set beresp.uncacheable = true;
    return (deliver);
  }

  # strip the port from a redirect just in case
  if (beresp.status == 301 || beresp.status == 302) {
    set beresp.http.Location = regsub(beresp.http.Location, ":[0-9]+", "");
  }

  if (beresp.status == 500 || beresp.status == 502 || beresp.status == 503 || beresp.status == 504) {
    return (abandon);
  }

  set beresp.grace = 5m;

  return (deliver);
}

sub vcl_deliver {
  if (obj.hits > 0) {
    set resp.http.X-Cache = "HIT";  
  } else {
    set resp.http.X-Cache = "MISS";  
  }
  
  unset resp.http.X-Powered-By; # express, asp.net
  unset resp.http.Server; # IIS
  unset resp.http.X-AspNet-Version; # duh

  return (deliver);
}
