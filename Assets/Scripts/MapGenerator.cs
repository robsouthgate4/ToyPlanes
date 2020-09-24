using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class MapGenerator : MonoBehaviour
{

    public int width;
    public int height;

    public float scale;

    public bool autoUpdate;

    public int octaves;
    
    [ Range(0, 1) ]
    public float persistance;
    public float lacunarity;

    public int seed = 1;
    public Vector2 offset;

    public void GenerateMap() {

        float[,] noiseMap = Noise.GenerateNoiseMap(width, height, seed, scale, octaves, persistance, lacunarity, offset);

        MapDisplay display = FindObjectOfType<MapDisplay>();
        display.DrawNoiseMap(noiseMap);
    }

    private void OnValidate()
    {

        if ( width < 1 )
        {
            width = 1;
        }

        if ( height < 1 )
        {
            height = 1;
        }

        if ( lacunarity < 1 )
        {
            lacunarity = 1;
        }

        if ( octaves < 0 )
        {
            octaves = 0;
        }

    }

}
