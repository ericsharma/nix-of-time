"""BlueZ pairing agent for nxbt: accepts pairing only from allowed Switches.

The Switch 2 pairs with "No Bonding", so no link key is stored and every
reconnect is a new Secure Simple Pairing that someone must confirm. This
agent confirms it for the addresses given on the command line and rejects
every other device.

Usage: nxbt-agent.py AA:BB:CC:DD:EE:FF [...]
"""

import sys

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

AGENT_PATH = "/nxbt/agent"
BUS = None
ALLOWED = {a.upper() for a in sys.argv[1:]}


class Rejected(dbus.DBusException):
    _dbus_error_name = "org.bluez.Error.Rejected"


def address_of(device_path):
    # /org/bluez/hci0/dev_A4_C1_E8_E0_74_99 -> A4:C1:E8:E0:74:99
    return device_path.rsplit("/", 1)[-1].removeprefix("dev_").replace("_", ":").upper()


def trust_later(device):
    """Mark the device Trusted, as the bluetoothctl flow that worked did.
    An untrusted device needs authorization for each service; the HID
    connection the Switch opens right after pairing is one."""
    def set_trusted():
        try:
            props = dbus.Interface(BUS.get_object("org.bluez", device),
                                   "org.freedesktop.DBus.Properties")
            props.Set("org.bluez.Device1", "Trusted", dbus.Boolean(True))
            print(f"trusted {address_of(device)}", flush=True)
        except dbus.DBusException as e:
            print(f"could not trust {address_of(device)}: {e}", flush=True)
        return False  # run once
    GLib.timeout_add(500, set_trusted)


def check(device, what):
    address = address_of(device)
    if address in ALLOWED:
        print(f"accept {what} from {address}", flush=True)
        trust_later(device)
        return
    print(f"reject {what} from {address}", flush=True)
    raise Rejected(f"{address} is not an allowed Switch")


class Agent(dbus.service.Object):
    @dbus.service.method("org.bluez.Agent1", in_signature="", out_signature="")
    def Release(self):
        print("released by bluetoothd", flush=True)

    @dbus.service.method("org.bluez.Agent1", in_signature="ou", out_signature="")
    def RequestConfirmation(self, device, passkey):
        check(device, f"confirmation {passkey:06d}")

    @dbus.service.method("org.bluez.Agent1", in_signature="o", out_signature="")
    def RequestAuthorization(self, device):
        check(device, "authorization")

    @dbus.service.method("org.bluez.Agent1", in_signature="os", out_signature="")
    def AuthorizeService(self, device, uuid):
        check(device, f"service {uuid}")

    @dbus.service.method("org.bluez.Agent1", in_signature="o", out_signature="s")
    def RequestPinCode(self, device):
        raise Rejected("PIN pairing is not used by the Switch")

    @dbus.service.method("org.bluez.Agent1", in_signature="o", out_signature="u")
    def RequestPasskey(self, device):
        raise Rejected("passkey entry is not used by the Switch")

    @dbus.service.method("org.bluez.Agent1", in_signature="ouq", out_signature="")
    def DisplayPasskey(self, device, passkey, entered):
        pass

    @dbus.service.method("org.bluez.Agent1", in_signature="os", out_signature="")
    def DisplayPinCode(self, device, pincode):
        pass

    @dbus.service.method("org.bluez.Agent1", in_signature="", out_signature="")
    def Cancel(self):
        print("request cancelled", flush=True)


def main():
    if not ALLOWED:
        sys.exit("give at least one allowed Switch address")
    global BUS
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = BUS = dbus.SystemBus()
    Agent(bus, AGENT_PATH)
    manager = dbus.Interface(bus.get_object("org.bluez", "/org/bluez"), "org.bluez.AgentManager1")
    # KeyboardDisplay is what bluetoothctl registers; it produced the
    # confirmation flow that worked with the Switch 2.
    manager.RegisterAgent(AGENT_PATH, "KeyboardDisplay")
    manager.RequestDefaultAgent(AGENT_PATH)
    print(f"agent registered for {sorted(ALLOWED)}", flush=True)
    GLib.MainLoop().run()


if __name__ == "__main__":
    main()
