#!/usr/bin/env sh

#
#NIC_Token="sdfsdfsdfljlbjkljlkjsdfoiwjedfglgkdlfgkfgldfkg"
#
#NIC_Username="000000/NIC-D"

#NIC_Password="xxxxxxx"

NIC_Api="https://api.nic.ru"

dns_nic_add() {
  fulldomain="${1}"
  txtvalue="${2}"

  NIC_Token="${NIC_Token:-$(_readaccountconf_mutable NIC_Token)}"
  NIC_Username="${NIC_Username:-$(_readaccountconf_mutable NIC_Username)}"
  NIC_Password="${NIC_Password:-$(_readaccountconf_mutable NIC_Password)}"
  if [ -z "$NIC_Token" ] || [ -z "$NIC_Username" ] || [ -z "$NIC_Password" ]; then
    NIC_Token=""
    NIC_Username=""
    NIC_Password=""
    _err "You must export variables: NIC_Token, NIC_Username and NIC_Password"
    return 1
  fi

  _saveaccountconf_mutable NIC_Customer "$NIC_Token"
  _saveaccountconf_mutable NIC_Username "$NIC_Username"
  _saveaccountconf_mutable NIC_Password "$NIC_Password"

  if ! _nic_get_authtoken "$NIC_Username" "$NIC_Password" "$NIC_Token"; then
    _err "get NIC auth token failed"
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "Invalid domain"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"
  _debug _service "$_service"

  _info "Adding record"
  if ! _nic_rest PUT "services/$_service/zones/$_domain/records" "<?xml version=\"1.0\" encoding=\"UTF-8\" ?><request><rr-list><rr><name>$_sub_domain</name><type>TXT</type><txt><string>$txtvalue</string></txt></rr></rr-list></request>"; then
    _err "Add TXT record error"
    return 1
  fi

  if ! _nic_rest POST "services/$_service/zones/$_domain/commit" ""; then
    return 1
  fi
  _info "Added, OK"
}

dns_nic_rm() {
  fulldomain="${1}"
  txtvalue="${2}"

  NIC_Token="${NIC_Token:-$(_readaccountconf_mutable NIC_Token)}"
  NIC_Username="${NIC_Username:-$(_readaccountconf_mutable NIC_Username)}"
  NIC_Password="${NIC_Password:-$(_readaccountconf_mutable NIC_Password)}"
  if [ -z "$NIC_Token" ] || [ -z "$NIC_Username" ] || [ -z "$NIC_Password" ]; then
    NIC_Token=""
    NIC_Username=""
    NIC_Password=""
    _err "You must export variables: NIC_Token, NIC_Username and NIC_Password"
    return 1
  fi

  if ! _nic_get_authtoken "$NIC_Username" "$NIC_Password" "$NIC_Token"; then
    _err "get NIC auth token failed"
    return 1
  fi

  if ! _get_root "$fulldomain"; then
    _err "Invalid domain"
    return 1
  fi
  
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"
  _debug _service "$_service"

  if ! _nic_rest GET "services/$_service/zones/$_domain/records"; then
    _err "Get records error"
    return 1
  fi

  _domain_id=$(printf "%s" "$response" | grep "$_sub_domain" | grep "$txtvalue" | sed -r "s/.*<rr id=\"(.*)\".*/\1/g")

  if ! _nic_rest DELETE "services/$_service/zones/$_domain/records/$_domain_id"; then
    _err "Delete record error"
    return 1
  fi

  if ! _nic_rest POST "services/$_service/zones/$_domain/commit" ""; then
    return 1
  fi
}

####################  Private functions below ##################################

_nic_get_authtoken() {
  username="$1"
  password="$2"
  token="$3"

  _info "Getting NIC auth token"

  export _H1="Authorization: Basic $token"
  export _H2="Content-Type: application/x-www-form-urlencoded"

  res="$(_post "grant_type=password&username=$username&password=$password&scope=%28GET%7CPUT%7CPOST%7CDELETE%29%3A%2Fdns-master%2F.%2B" "$NIC_Api/oauth/token" "" "POST")"
  if _contains "$res" "access_token"; then
    _auth_token=$(printf "%s" "$res" | cut -d , -f2 | tr -d "\"" | sed "s/access_token://")
    _info "Token received"
    _debug _auth_token "$_auth_token"
    return 0
  fi
  return 1
}

_get_root() {
  domain="$1"
  i=1
  p=1

  if ! _nic_rest GET "zones"; then
  return 1
  fi

  _all_domains=$(printf "%s" "$response" | grep "idn-name" | sed -r "s/.*idn-name=\"(.*)\" name=.*/\1/g")
  _debug2 _all_domains "$_all_domains"

  while true; do
   h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
   _debug h "$h"

   if [ -z "$h" ]; then
     return 1
   fi

   if _contains "$_all_domains" "^$h$"; then
     _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
     _domain=$h
     _service=$(printf "%s" "$response" | grep "$_domain" | sed -r "s/.*service=\"(.*)\".*$/\1/")
     return 0
   fi
   p="$i"
   i=$(_math "$i" + 1)
  done
  return 1
}

_nic_rest() {
  m="$1"
  ep="$2"
  data="$3"
  _debug "$ep"

  export _H1="Content-Type: application/xml"
  export _H2="Authorization: Bearer $_auth_token"

  if [ "$m" != "GET" ]; then
  _debug data "$data"
  response=$(_post "$data" "$NIC_Api/dns-master/$ep" "" "$m")
  else
  response=$(_get "$NIC_Api/dns-master/$ep")
  fi

  if _contains "$response" "<errors>"; then
  error=$(printf "%s" "$response" | grep "error code" | sed -r "s/.*<error code=.*>(.*)<\/error>/\1/g")
  _err "Error: $error"
  return 1
  fi

  if ! _contains "$response" "<status>success</status>"; then
   return 1
  fi
  _debug2 response "$response"
  return 0
}
