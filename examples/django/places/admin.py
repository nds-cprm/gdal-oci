from django.contrib.gis import admin

from .models import Place


@admin.register(Place)
class PlaceAdmin(admin.GISModelAdmin):
    list_display = ["name"]
