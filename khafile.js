
let project = new Project("ArmorPad");
project.addSources("Sources");
project.addShaders("armorcore/Shaders/*.glsl");
project.addAssets("Assets/*", { destination: "data/{name}" });
project.addAssets("Assets/themes/*.json", { destination: "data/themes/{name}" });
project.addLibrary("zui");
resolve(project);
