#include <stdio.h>
int main(int argc, char *argv[], char *envp[])
{
	int i = 0;
	while (argv[i]) {
		printf("argv %d %s\n", i, argv[i]);
		i++;
	}
	i = 0;
	while (envp[i]) {
		printf("envp %d %s\n", i, envp[i]);
		i++;
	}
	return 0;
}
