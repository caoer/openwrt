include $(TOPDIR)/rules.mk

PKG_NAME:=glrobot-base
PKG_VERSION:=1.0
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/glrobot-base
  SECTION:=base
  CATEGORY:=Base system
  TITLE:=Robot fleet base: first-boot defaults, health daemon, RPCD ACL
  PKGARCH:=all
endef

define Package/glrobot-base/description
 Fleet management base package (patterns adapted from Lean's LEDE):
 - zzz uci-defaults: atomic first-boot setup, MAC-suffix hostname, NTP, version branding
 - glrobot-health: procd-respawned telemetry daemon writing JSON to /tmp/state/glrobot.json
 - RPCD ACL exposing the telemetry file for remote controller polling via ubus
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/glrobot-base/install
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/zzz-glrobot-defaults $(1)/etc/uci-defaults/zzz-glrobot-defaults
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./files/glrobot-health $(1)/usr/sbin/glrobot-health
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/glrobot-health.init $(1)/etc/init.d/glrobot-health
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./files/glrobot.acl.json $(1)/usr/share/rpcd/acl.d/glrobot.json
endef

$(eval $(call BuildPackage,glrobot-base))
