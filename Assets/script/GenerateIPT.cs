using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class GenerateIPT : MonoBehaviour
{
    public GameObject prefabs;
    private Stack<GameObject> Clone = new Stack<GameObject>();
    
    public float radius;
    public int count;
    public void BuildObj()
    {
        for (int i = 0; i < count; i++) {
            Vector2 p = Random.insideUnitCircle * radius;
            Vector3 pos2 = new Vector3(p.x,0,p.y);
            GameObject obj1 = Instantiate(prefabs, pos2, Quaternion.identity);
            //obj.transform.localScale = new Vector3(Random.Range(0.7, 1.3));
            Clone.Push(obj1);
        }
    }

    public void destroyObj()
    {
        while (Clone.Count != 0)
        {
            GameObject.DestroyImmediate(Clone.Pop(),true);
        }
       
    }
}
