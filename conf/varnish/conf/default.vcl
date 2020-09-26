# Inspired by http://www.htpcguides.com/configure-wordpress-varnish-4-cache-with-apache-or-nginx/
#
# This is an example VCL file for Varnish.
#
# It does not do anything by default, delegating control to the
# builtin VCL. The builtin VCL is called when there is no explicit
# return statement.
#
# See the VCL chapters in the Users Guide at https://www.varnish-cache.org/docs/
# and https://www.varnish-cache.org/trac/wiki/VCLExamples for more examples.

# Marker to tell the VCL compiler that this VCL has been adapted to the
# new 4.0 format.

vcl 4.0;

import directors;
import std;

backend default {
  .port = "80";
  .host = "wordpress";
  .first_byte_timeout = 60s;
  .connect_timeout = 300s;
}

# SET THE ALLOWED IP OF PURGE REQUESTS
# ##########################################################
acl purge {
  "127.0.0.1";
}

#THE RECV FUNCTION
# ##########################################################
sub vcl_recv {

  # Only a single backend
  set req.backend_hint = default;

  # Setting http headers for backend
  set req.http.X-Forwarded-For = req.http.X-Real-IP;

  # Purge request check sections for hash_always_miss, purge and ban
  # BLOCK IF NOT IP is not in purge acl
  # ##########################################################

  # Enable smart refreshing using hash_always_miss
  if (req.http.Cache-Control ~ "no-cache") {
    if (client.ip ~ purge) {
      set req.hash_always_miss = true;
    }
  }

  if (req.method == "PURGE") {
    if (!client.ip ~ purge) {
      return(synth(405, "Not allowed."));
    }

    return (purge);
  }

  if (req.method == "BAN") {
    if (!client.ip ~ purge) {
      return(synth(403, "Not allowed."));
    }

    ban("req.http.host == " + req.http.host + " && req.url == " + req.url);

    # Throw a synthetic page so the
    # request won't go to the backend.
    return(synth(200, "Ban added"));
  }

  # Unset Cloudflare cookies
  # Remove has_js and CloudFlare/Google Analytics __* cookies.
  set req.http.Cookie = regsuball(req.http.Cookie, "(^|;\s*)(_[_a-z]+|has_js)=[^;]*", "");
  # Remove a ";" prefix, if present.
  set req.http.Cookie = regsub(req.http.Cookie, "^;\s*", "");

  # DO NOT CACHE RSS FEED
  if (req.url ~ "/feed(/)?") {
    return ( pass );
  }

  # Pass wp-cron
  if (req.url ~ "wp-cron\.php.*") {
    return ( pass );
  }

  ## Do not cache search results, comment these 3 lines if you do want to cache them
  if (req.url ~ "/\?s\=") {
    return ( pass );
  }

  # CLEAN UP THE ENCODING HEADER.
  # SET TO GZIP, DEFLATE, OR REMOVE ENTIRELY.  WITH VARY ACCEPT-ENCODING
  # VARNISH WILL CREATE SEPARATE CACHES FOR EACH
  # DO NOT ACCEPT-ENCODING IMAGES, ZIPPED FILES, AUDIO, ETC.
  # ##########################################################
  if (req.http.Accept-Encoding) {
    if (req.url ~ "\.(jpg|png|gif|gz|tgz|bz2|tbz|mp3|ogg)$") {
      # No point in compressing these
      unset req.http.Accept-Encoding;
    } elsif (req.http.Accept-Encoding ~ "gzip") {
      set req.http.Accept-Encoding = "gzip";
    } elsif (req.http.Accept-Encoding ~ "deflate") {
      set req.http.Accept-Encoding = "deflate";
    } else {
      unset req.http.Accept-Encoding; # unknown algorithm
    }
  }

  # PIPE ALL NON-STANDARD REQUESTS
  # ##########################################################
  if (req.method != "GET" &&
    req.method != "HEAD" &&
    req.method != "PUT" &&
    req.method != "POST" &&
    req.method != "TRACE" &&
    req.method != "OPTIONS" &&
    req.method != "DELETE") {
    return (pipe);
  }

  # ONLY CACHE GET AND HEAD REQUESTS
  # ##########################################################
  if (req.method != "GET" && req.method != "HEAD") {
    return (pass);
  }

  # OPTIONAL: DO NOT CACHE LOGGED IN USERS (THIS OCCURS IN FETCH TOO, EITHER
  # COMMENT OR UNCOMMENT BOTH
  # ##########################################################
  if ( req.http.cookie ~ "wordpress_logged_in|resetpass" ) {
    return( pass );
  }

  #fix CloudFlare Mixed Content with Flexible SSL
  if (req.http.X-Forwarded-Proto) {
    return(hash);
  }

  # IF THE REQUEST IS NOT FOR A PREVIEW, WP-ADMIN OR WP-LOGIN
  # THEN UNSET THE COOKIES
  # ##########################################################
  if (!(req.url ~ "wp-(login|admin)")
    && !(req.url ~ "&preview=true" )
  ){
    unset req.http.cookie;
  }

  # IF BASIC AUTH IS ON THEN DO NOT CACHE
  # ##########################################################
  if (req.http.Authorization || req.http.Cookie) {
    return (pass);
  }

  # IF YOU GET HERE THEN THIS REQUEST SHOULD BE CACHED
  # ##########################################################
  return (hash);
}

sub vcl_hash {
  # The following url transformations help Varnish cache fewer
  # versions of the same content by ignoring marketing url parameters
  # and hashes.
  #
  # req.http.newUrl replaces req.url *for cache validation only*
  # Marketing parameters and hashes must still be sent to the backend
  # b/c even though they don't influence content, they should be included
  # in any redirects the backend generates.

  # Ignore marketing-related url parameters when caching urls
  #   utm_ (Google Analytics)
  #   gclid, cx, ie, cof, siteurl (not sure what these do)
  #   gc_source (Goshen College internal campaign tracking)
  #   mkt_tok (Marketo email click tracking)
  set req.http.newUrl = req.url;

  if (req.http.newUrl ~ "(\?|&)(utm_source|utm_medium|utm_campaign|utm_content|gclid|cx|ie|cof|siteurl|gc_source|mkt_tok)=") {
    set req.http.newUrl = regsuball(req.http.newUrl, "&(utm_source|utm_medium|utm_campaign|utm_content|gclid|cx|ie|cof|siteurl|gc_source|mkt_tok)=([A-z0-9_\-\.%25]+)", "");
    set req.http.newUrl = regsuball(req.http.newUrl, "\?(utm_source|utm_medium|utm_campaign|utm_content|gclid|cx|ie|cof|siteurl|gc_source|mkt_tok)=([A-z0-9_\-\.%25]+)", "?");
    set req.http.newUrl = regsub(req.http.newUrl, "\?&", "?");
    set req.http.newUrl = regsub(req.http.newUrl, "\?$", "");
  }

  # Ignore hash when caching urls
  if (req.http.newUrl ~ "\#") {
    set req.http.newUrl = regsub(req.http.newUrl, "\#.*$", "");
  }

  # Default vcl_hash, except replaced "req.url" with "req.http.newUrl"
  hash_data(req.http.newUrl);

  if (req.http.host) {
    hash_data(req.http.host);
  } else {
    hash_data(server.ip);
  }

  return (lookup);
}

# HIT FUNCTION
# ##########################################################
sub vcl_hit {
  return (deliver);
}

# MISS FUNCTION
# ##########################################################
sub vcl_miss {
  return (fetch);
}

# FETCH FUNCTION
# ##########################################################
sub vcl_backend_response {
  # I SET THE VARY TO ACCEPT-ENCODING, THIS OVERRIDES W3TC
  # TENDANCY TO SET VARY USER-AGENT.  YOU MAY OR MAY NOT WANT
  # TO DO THIS
  # ##########################################################
  set beresp.http.Vary = "Accept-Encoding";

  # IF NOT WP-ADMIN THEN UNSET COOKIES AND SET THE AMOUNT OF
  # TIME THIS PAGE WILL STAY CACHED (TTL), add other locations or subdomains you do not want to cache here in case they set cookies
  # ##########################################################
  if (!(bereq.url ~ "wp-(login|admin)") && !bereq.http.cookie ~ "wordpress_logged_in|resetpass" ) {
    unset beresp.http.set-cookie;
    set beresp.ttl = 1w;
    set beresp.grace = 3d;
  }

  if (beresp.ttl <= 0s ||
    beresp.http.Set-Cookie ||
    beresp.http.Vary == "*") {
    set beresp.ttl = 120 s;
    set beresp.uncacheable = true;
    return (deliver);
  }

  return (deliver);
}

# DELIVER FUNCTION
# ##########################################################
sub vcl_deliver {
  # IF THIS PAGE IS ALREADY CACHED THEN RETURN A 'HIT' TEXT
  # IN THE HEADER (GREAT FOR DEBUGGING)
  # ##########################################################
  if (obj.hits > 0) {
    set resp.http.X-Cache = "HIT";
  } else {
    set resp.http.X-Cache = "MISS";
  }

  # Please note that obj.hits behaviour changed in 4.0, now it counts per objecthead, not per object
  # and obj.hits may not be reset in some cases where bans are in use. See bug 1492 for details.
  # So take hits with a grain of salt
  set resp.http.X-Cache-Hits = obj.hits;

  # Remove some headers to improve security
  unset resp.http.Via;
  unset resp.http.X-Powered-By;
  unset resp.http.Server;
}
