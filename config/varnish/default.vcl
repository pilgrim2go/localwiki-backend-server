# This is a basic VCL configuration file for varnish.  See the vcl(7)
# man page for details on VCL syntax and semantics.
# 
# Default backend definition.  Set this to point to your content
# server.

 backend localwiki { 
     .host = "127.0.0.1";
     .port = "8084";

     .connect_timeout = 600s;
     .first_byte_timeout = 600s;
     .between_bytes_timeout = 600s;
 }
 
sub vcl_recv {
    # unless sessionid/csrftoken is in the request, don't pass ANY cookies (referral_source, utm, etc)
    if (req.request == "GET" && (req.url ~ "^/static" || (req.http.cookie !~ "sessionid" && req.http.cookie !~ "csrftoken"))) {
        remove req.http.Cookie;
    }

    # normalize accept-encoding to account for different browsers
    # see: https://www.varnish-cache.org/trac/wiki/VCLExampleNormalizeAcceptEncoding
    if (req.http.Accept-Encoding) {
        if (req.http.Accept-Encoding ~ "gzip") {
            set req.http.Accept-Encoding = "gzip";
        } elsif (req.http.Accept-Encoding ~ "deflate") {
            set req.http.Accept-Encoding = "deflate";
        } else {
            # unknown algorithm
            remove req.http.Accept-Encoding;
        }
    }

    # Allow the backend to serve up stale content if it is responding slowly.
    set req.grace = 6h;

    if (req.http.x-forwarded-host == "www.{{ public_hostname }}" || req.http.x-forwarded-host == "{{ public_hostname }}") {
       set req.http.host = "{{ public_hostname }}";
       set req.backend = localwiki;
    } else {
       set req.http.host = req.http.x-forwarded-host;
       set req.backend = localwiki;
    }

    if (req.http.x-forwarded-for) {
       set req.http.X-Forwarded-For =
           req.http.X-Forwarded-For + ", " + client.ip;
    } else {
       set req.http.X-Forwarded-For = client.ip;
    }
    if (req.request != "GET" &&
      req.request != "HEAD" &&
      req.request != "PUT" &&
      req.request != "POST" &&
      req.request != "TRACE" &&
      req.request != "OPTIONS" &&
      req.request != "DELETE") {
        /* Non-RFC2616 or CONNECT which is weird. */
        return (pipe);
    }
    if (req.request != "GET" && req.request != "HEAD") {
        /* We only deal with GET and HEAD by default */
        return (pass);
    }
    return (lookup);
}

sub vcl_fetch {
    # static files always cached
    if (req.url ~ "^/static" || req.url ~ "^/media") {
       unset beresp.http.set-cookie;
       return (deliver);
    }

     /* Remove Expires from backend, it's not long enough */
     /* unset beresp.http.expires; */

     /* Set the clients TTL on this object */
     /* set beresp.http.cache-control = "max-age=900"; */

     /* Set how long Varnish will keep it */
     /* set beresp.ttl = 20w; */

     /* marker for vcl_deliver to reset Age: */
     /* set beresp.http.magicmarker = "1"; */

    # pass through for anything with a session/csrftoken set
    if (beresp.http.set-cookie ~ "sessionid" || beresp.http.set-cookie ~ "csrftoken") {
       return (hit_for_pass);
    } else {
       return (deliver);
    }
}

sub vcl_deliver {
    if (resp.http.magicmarker) {
        /* Remove the magic marker */
        unset resp.http.magicmarker;

        /* By definition we have a fresh object */
        set resp.http.age = "0";
    }
    return (deliver);
}
