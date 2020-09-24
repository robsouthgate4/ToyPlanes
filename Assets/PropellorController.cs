using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class PropellorController : MonoBehaviour
{

    [SerializeField]
    private float speed = 1000f;

    private float rotationZ;

    void Start()
    {

        rotationZ = 0f;
        
    }
    
    void Update()
    {

        rotationZ += speed * Time.deltaTime;

        transform.localRotation = Quaternion.Euler( 0f, 0f, rotationZ );

    }
}
