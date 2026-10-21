from django.contrib.gis.db.models.functions import Distance
from django.contrib.gis.geos import Point
from django.contrib.gis.measure import D
from django.core.serializers import serialize
from django.db import connection
from django.http import HttpResponse, HttpResponseBadRequest, JsonResponse

from .models import Place


def places_geojson(request):
    data = serialize("geojson", Place.objects.all(), geometry_field="location", fields=["name"])
    return HttpResponse(data, content_type="application/geo+json")


def places_near(request):
    """GET /places/near?lon=-43.2&lat=-22.9&km=500 — consulta espacial executada no PostGIS."""
    try:
        point = Point(float(request.GET["lon"]), float(request.GET["lat"]), srid=4326)
        km = float(request.GET.get("km", 100))
    except (KeyError, ValueError):
        return HttpResponseBadRequest("parâmetros: lon, lat e km (opcional)")

    places = (
        # distance_lte (e não dwithin): em SRID 4326, dwithin só aceita distância em graus
        Place.objects.filter(location__distance_lte=(point, D(km=km)))
        .annotate(distance=Distance("location", point))
        .order_by("distance")
    )
    return JsonResponse(
        {"results": [{"name": p.name, "km": round(p.distance.km, 1)} for p in places]}
    )


def health(request):
    from django.contrib.gis import gdal, geos

    with connection.cursor() as cursor:
        cursor.execute("SELECT postgis_lib_version()")
        postgis = cursor.fetchone()[0]
    return JsonResponse(
        {"gdal": gdal.gdal_full_version().decode(), "geos": geos.geos_version().decode(), "postgis": postgis}
    )
