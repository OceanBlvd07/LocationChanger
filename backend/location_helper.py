import argparse
import asyncio
import math
import signal
import sys

from pymobiledevice3.remote.userspace_tunnel import UserspaceRsdTunnel
from pymobiledevice3.services.dvt.instruments.dvt_provider import DvtProvider
from pymobiledevice3.services.dvt.instruments.location_simulation import (
    LocationSimulation,
)
from pymobiledevice3.services.dvt.instruments.device_info import DeviceInfo


def parse_arguments():
    parser = argparse.ArgumentParser(
        description="Simulate location without blocking the developer tunnel."
    )

    parser.add_argument("latitude", type=float)
    parser.add_argument("longitude", type=float)

    # Optional explicit device selection.
    parser.add_argument("--udid")

    args = parser.parse_args()

    if not math.isfinite(args.latitude) or not -90 <= args.latitude <= 90:
        parser.error("Latitude must be a finite number between -90 and 90.")

    if not math.isfinite(args.longitude) or not -180 <= args.longitude <= 180:
        parser.error("Longitude must be a finite number between -180 and 180.")

    return args


async def run_simulation(args):
    stop_requested = asyncio.Event()
    loop = asyncio.get_running_loop()

    # Signals request graceful cleanup instead of abruptly ending the process.
    for stop_signal in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(stop_signal, stop_requested.set)

    try:
        print("Connecting to the developer services…", flush=True)

        # Own the tunnel explicitly so it stays available during simulation
        # and is closed when we leave this context.
        async with UserspaceRsdTunnel(
            serial=args.udid,
            autopair=False,
        ) as rsd:
            async with DvtProvider(rsd) as dvt:
                # Both services share the same developer connection.
                async with LocationSimulation(dvt) as location, DeviceInfo(dvt) as info:
                    # If Stop was requested during setup, don't start.
                    if stop_requested.is_set():
                        print("Stopped before simulation started.", flush=True)
                        return

                    try:
                        await location.set(args.latitude, args.longitude)

                        print(
                            "Simulation command completed. Verify in Maps.",
                            flush=True,
                        )
                        print("Press Ctrl+C to stop and clear.", flush=True)

                        # Unlike signal.sigwait(), this yields control.
                        # The same event loop can keep processing the tunnel.
                       # Probe the existing developer connection without resetting location.
                        while not stop_requested.is_set():
                            try:
                                await asyncio.wait_for(
                                    stop_requested.wait(),
                                    timeout=5,
                                )
                            except asyncio.TimeoutError:
                                print("Checking existing developer connection…", flush=True)

                                await asyncio.wait_for(
                                    info.mach_kernel_name(),
                                    timeout=3,
                                )

                                print("Existing developer connection responded.", flush=True)
                    finally:
                        # Clear while the original developer connection
                        # and location service are still open.
                        print("Sending location-clear command…", flush=True)

                        await asyncio.wait_for(
                            location.clear(),
                            timeout=10,
                        )
                        # Complete another round trip before closing the developer connection.
                        # This checks responsiveness; it is not confirmation of GPS restoration.
                        await asyncio.wait_for(
                            info.mach_kernel_name(),
                            timeout=3,
                        )

                        print("Developer connection responded after clear.", flush=True)

                        # This is command completion, not GPS verification.
                        print(
                            "Clear command sent. Verify real location in Maps.",
                            flush=True,
                        )
    finally:
        for stop_signal in (signal.SIGINT, signal.SIGTERM):
            loop.remove_signal_handler(stop_signal)


def main():
    args = parse_arguments()

    try:
        asyncio.run(run_simulation(args))
    except KeyboardInterrupt:
        print(
            "Interrupted. Location restoration is unconfirmed.",
            file=sys.stderr,
            flush=True,
        )
        return 1
    except Exception as error:
        print(
            f"{type(error).__name__}: {error}",
            file=sys.stderr,
            flush=True,
        )
        print(
            "The operation did not finish successfully. "
            "Verify the phone's location before starting another session.",
            file=sys.stderr,
            flush=True,
        )
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())