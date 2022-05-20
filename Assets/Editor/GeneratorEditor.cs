using UnityEngine;
using UnityEditor;

[CustomEditor(typeof(GenerateIPT))]
public class GeneratorEditor : Editor {
    public override void OnInspectorGUI() {
        DrawDefaultInspector();

        GenerateIPT myScript = (GenerateIPT)target;
        if(GUILayout.Button("创建对象")) {
            myScript.BuildObj();
        }
        if(GUILayout.Button("销毁对象")) {
            myScript.destroyObj();
        }
    }
}
