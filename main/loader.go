components {
  id: "script"
  component: "/main/loader.script"
}
embedded_components {
  id: "proxy_menu"
  type: "collectionproxy"
  data: "collection: \"/main/ui/menu.collection\"\nexclude: false\n"
}
embedded_components {
  id: "proxy_match"
  type: "collectionproxy"
  data: "collection: \"/main/match/match.collection\"\nexclude: false\n"
}
