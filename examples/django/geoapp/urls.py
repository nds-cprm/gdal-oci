from django.contrib import admin
from django.urls import path

from places import views

urlpatterns = [
    path("admin/", admin.site.urls),
    path("places.geojson", views.places_geojson, name="places-geojson"),
    path("places/near", views.places_near, name="places-near"),
    path("health", views.health, name="health"),
]
