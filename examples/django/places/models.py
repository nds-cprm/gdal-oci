from django.contrib.gis.db import models


class Place(models.Model):
    name = models.CharField(max_length=200)
    location = models.PointField(srid=4326)

    def __str__(self):
        return self.name
