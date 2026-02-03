from titiler.core.factory import TilerFactory
from titiler.image.factory import IIIFFactory, LocalTilerFactory, MetadataFactory, TilerFactory
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(title="titiler + titiler-image")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Metadata 
meta = MetadataFactory()
app.include_router(meta.router, tags=["Metadata"])

# COG 
cog = TilerFactory()
app.include_router(cog.router, prefix="/cog", tags=["COG"])

# IIIF 
iiif = IIIFFactory(router_prefix="/iiif")
app.include_router(iiif.router, prefix="/iiif", tags=["IIIF"])

# 90% sure its useless 
local = LocalTilerFactory(router_prefix="/image")
app.include_router(local.router, prefix="/image", tags=["Local Tiles"])
#tms
local = TilerFactory(router_prefix="/tiles")
app.include_router(local.router, prefix="/tiles", tags=["TMS TILES"])

@app.get("/healthz")
def health():
    """Health check."""
    return {"ping": "pong!"}