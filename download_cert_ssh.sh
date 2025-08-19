import ssl
from urllib3.util.ssl_ import create_urllib3_context
from requests.adapters import HTTPAdapter
import requests

class CurlLikeAdapter(HTTPAdapter):
    def init_poolmanager(self, *args, **kwargs):
        ctx = create_urllib3_context()
        # Match curl's negotiated protocol (example: TLSv1.2)
        ctx.minimum_version = ssl.TLSVersion.TLSv1_2
        ctx.maximum_version = ssl.TLSVersion.TLSv1_2
        # Optionally pin cipher suite (example from curl output)
        # ctx.set_ciphers("AES256-GCM-SHA384:@SECLEVEL=1")
        # If you need to relax legacy servers with OpenSSL 1.1.1d:
        # ctx.set_ciphers("DEFAULT:@SECLEVEL=1")
        kwargs["ssl_context"] = ctx
        return super().init_poolmanager(*args, **kwargs)

s = requests.Session()
s.trust_env = False  # ignore proxies/REQUESTS_CA_BUNDLE if you want parity
s.mount("https://", CurlLikeAdapter())

r = s.get("https://host/path",
          # Use the same CA that curl trusts (see B below)
          verify="/path/to/your-ca-bundle.pem",
          # If your curl used -u user:pass:
          auth=("user", "pass"),
          timeout=20)
print(r.status_code)
