import unit_threaded.runner;

int main(string[] arguments)
{
    return arguments.runTests!("selector.model_test", "selector.theme_test");
}
