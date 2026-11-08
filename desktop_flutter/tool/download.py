"""Download pinned build inputs with retries.

GitHub's release CDN occasionally answers 5xx or drops a connection. These
files are only needed once per job, so a few retries turn a flaky network into
a successful build.
"""

import http.client
import shutil
import time
import urllib.error
import urllib.request
from pathlib import Path

# Seconds to wait before attempts 2..7.
RETRY_DELAYS = (10, 30, 60, 120, 180, 300)


def fetch(url, destination, timeout=90, delays=RETRY_DELAYS):
    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(destination.name + ".part")
    last = None
    for delay in (0,) + tuple(delays):
        if delay:
            time.sleep(delay)
        try:
            with urllib.request.urlopen(url, timeout=timeout) as incoming:
                with temporary.open("wb") as outgoing:
                    shutil.copyfileobj(incoming, outgoing)
            temporary.replace(destination)
            return destination
        except urllib.error.HTTPError as error:
            last = error
            # Client errors will not heal by retrying.
            if error.code < 500 and error.code != 429:
                raise
        except (urllib.error.URLError, http.client.HTTPException,
                ConnectionError, TimeoutError, OSError) as error:
            last = error
        finally:
            temporary.unlink(missing_ok=True)
    raise last
