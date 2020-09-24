using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class PlaneMovement : MonoBehaviour
{

    [SerializeField]
    private float speed = 1.0f;

    [SerializeField]
    private float rotationSpeed = 1.0f;

    [SerializeField]
    private float rotationAmount = 20f;

    private Quaternion newRotation;
    private Vector3 lastPosition;

    private void Start()
    {

        newRotation         = new Quaternion();
        lastPosition        = new Vector3();

    }

    void Update()
    {

        Vector3 mousePosition = Input.mousePosition;

        Plane plane = new Plane( Vector3.up, transform.position );

        Ray ray = Camera.main.ScreenPointToRay(mousePosition);        

        float dist;

        plane.Raycast(ray, out dist);

        Vector3 pos = ray.GetPoint(dist);

        Vector3 positionDelta = transform.position - lastPosition;        

        var localDirection = transform.InverseTransformDirection(positionDelta);

        lastPosition = transform.position;

        float difference = Vector3.Distance(transform.position, pos);

        float rotZ = (-localDirection.x * difference) * rotationAmount;

        newRotation = Quaternion.Euler(0f, 0f, Mathf.Clamp( rotZ, -50f, 50f ) );

        transform.rotation = Quaternion.Lerp(transform.rotation, newRotation, rotationSpeed * Time.deltaTime);

        transform.position = Vector3.Lerp(transform.position, pos, speed * Time.deltaTime);

    }

}
