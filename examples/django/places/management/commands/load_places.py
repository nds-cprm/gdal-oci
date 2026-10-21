from django.contrib.gis.gdal import DataSource
from django.core.management.base import BaseCommand, CommandError

from places.models import Place


class Command(BaseCommand):
    help = (
        "Importa pontos de qualquer fonte que o GDAL da imagem abre "
        "(GeoJSON, GeoPackage, Shapefile, KML/KMZ, Parquet, WFS, OCI:..., PG:...)."
    )

    def add_arguments(self, parser):
        parser.add_argument("source", help="arquivo ou string de conexão GDAL")
        parser.add_argument("--layer", default="0", help="nome ou índice da camada (padrão: 0)")
        parser.add_argument("--name-field", default="name", help="campo com o nome do lugar (KML: Name)")

    def handle(self, source, layer, name_field, **options):
        ds = DataSource(source)
        layer = ds[int(layer)] if layer.isdigit() else ds[layer]
        if name_field not in layer.fields:
            raise CommandError(f"campo {name_field!r} não existe na camada {layer.name!r}: {layer.fields}")

        # feição a feição (e não LayerMapping): drivers como o LIBKML declaram a geometria da camada
        # como Unknown, mesmo quando todas as feições são pontos
        places = []
        for feature in layer:
            geom = feature.geom
            # Point ou Point25D (KML grava pontos 3D); MultiPoint e outros tipos são ignorados
            if not geom.geom_type.name.startswith("Point"):
                continue
            geom.coord_dim = 2  # o PointField do modelo é 2D
            geom.transform(4326)
            places.append(Place(name=feature.get(name_field), location=geom.geos))

        Place.objects.bulk_create(places)
        self.stdout.write(
            self.style.SUCCESS(
                f"{ds.driver} / {layer.name}: {len(places)} importados, {Place.objects.count()} lugares no banco"
            )
        )
