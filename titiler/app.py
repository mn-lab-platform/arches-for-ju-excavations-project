from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from titiler.core.factory import TilerFactory as CoreTilerFactory
from titiler.image.factory import IIIFFactory, LocalTilerFactory, MetadataFactory

app = FastAPI(title="titiler + titiler-image")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

meta = MetadataFactory()
app.include_router(meta.router, tags=["Metadata"])

cog = CoreTilerFactory()
app.include_router(cog.router, prefix="/cog", tags=["COG"])

iiif = IIIFFactory()
app.include_router(iiif.router, prefix="/iiif", tags=["IIIF"])

local_image = LocalTilerFactory()
app.include_router(local_image.router, prefix="/image", tags=["Local Tiles"])

tiles = CoreTilerFactory()
app.include_router(tiles.router, prefix="/tiles", tags=["TMS Tiles"])

@app.get("/healthz")
def health():
    return {"ping": "pong!"}