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
            float scale = Random.Range(35, 50);
            obj1.transform.localScale = new Vector3(scale,scale,scale);
            obj1.transform.rotation = Quaternion.Lerp(Random.rotation, Quaternion.identity, (float)0.85 ) ;
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
