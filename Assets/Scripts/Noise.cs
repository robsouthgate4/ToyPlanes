﻿using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public static class Noise
{

    public static float[,] GenerateNoiseMap( 
        int width, 
        int height, 
        int seed, 
        float scale, 
        int octaves, 
        float persistance, 
        float lacunarity,
        Vector2 offset)
    {

        // Generate random seed value for offsets

        System.Random prng = new System.Random( seed );

        Vector2[] octaveOffsets = new Vector2[ octaves ];

        float mapWidth  = width / 2f;
        float mapHeight = height / 2f;

        for (int i = 0; i < octaves; i++) {

            float offsetX = prng.Next(-100000, 100000) + offset.x;
            float offsetY = prng.Next(-100000, 100000) + offset.y;

            octaveOffsets[i] = new Vector2(offsetX, offsetY);

        }

        float[,] noiseMap = new float[ width, height ]; // Create 2D noise map array

        if ( scale <= 0 ) // Prevent 0 scale values
        {
            scale = 0.001f;
        }

        float maxNoiseHeight = float.MinValue;
        float minNoiseHeight = float.MaxValue;

        for (int y = 0; y < height; y++)
        {            
            for (int x = 0; x < width; x++) {

                float amplitude = 1;
                float frequency = 1;
                float noiseHeight = 0;

                for (int i = 0; i < octaves; i++)
                {

                    float sampleX = ( x - mapWidth ) / scale * frequency + octaveOffsets[ i ].x;
                    float sampleY = ( y - mapHeight ) / scale * frequency + octaveOffsets[ i ].y;

                    float perlinVal = Mathf.PerlinNoise(sampleX, sampleY) * 2 - 1; // Convert to -1 to 1 to get full range

                    noiseHeight += perlinVal * amplitude;

                    amplitude *= persistance;
                    frequency *= lacunarity;

                }                

                if ( noiseHeight > maxNoiseHeight ) // Track the lowest and highest numer in our range
                {

                    maxNoiseHeight = noiseHeight;

                } else if ( noiseHeight < minNoiseHeight )
                {

                    minNoiseHeight = noiseHeight;

                }

                noiseMap[x, y] = noiseHeight;
                
            }

        }

        // Remap values from lowest to highest vales, back to 0 - 1 range

        for (int y = 0; y < height; y++)
        {
            for (int x = 0; x < width; x++)
            {
                noiseMap[x, y] = Mathf.InverseLerp(minNoiseHeight, maxNoiseHeight, noiseMap[x, y]);
            }
        }

        return noiseMap;

    }

}
