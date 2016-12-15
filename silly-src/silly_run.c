#include <pthread.h>
#include <unistd.h>
#include <signal.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>

#include "silly.h"
#include "silly_env.h"
#include "silly_malloc.h"
#include "silly_timer.h"
#include "silly_socket.h"
#include "silly_worker.h"
#include "silly_daemon.h"

#include "silly_run.h"

struct {
	int exit;
	int run;
	pthread_mutex_t mutex;
	pthread_cond_t cond;
} R;


static void *
thread_timer(void *arg)
{
	(void)arg;
	for (;;) {
		silly_timer_update();
		if (R.exit)
			break;
		usleep(5000);
		if (silly_worker_msgsz() > 0)
			pthread_cond_signal(&R.cond);
	}
	silly_socket_terminate();
	return NULL;
}


static void *
thread_socket(void *arg)
{
	(void)arg;
	for (;;) {
		int err = silly_socket_poll();
		if (err < 0)
			break;
		pthread_cond_signal(&R.cond);
	}
	pthread_mutex_lock(&R.mutex);
	R.run = 0;
	pthread_cond_signal(&R.cond);
	pthread_mutex_unlock(&R.mutex);
	return NULL;
}

static void *
thread_worker(void *arg)
{
	struct silly_config *c;
	c = (struct silly_config *)arg;
	silly_worker_start(c);
	while (R.run) {
		silly_worker_dispatch();
		if (!R.run)
			break;
		//allow spurious wakeup, it's harmless
		pthread_mutex_lock(&R.mutex);
		if (R.run)
			pthread_cond_wait(&R.cond, &R.mutex);
		pthread_mutex_unlock(&R.mutex);
	}
	return NULL;
}

static int
signal_init()
{
	signal(SIGPIPE, SIG_IGN);
	return 0;
}

static void
thread_create(pthread_t *tid, void *(*start)(void *), void *arg)
{
	int err;
	err = pthread_create(tid, NULL, start, arg);
	if (err < 0) {
		fprintf(stderr, "thread create fail:%d\n", err);
		exit(-1);
	}
	return ;
}

void
silly_run(struct silly_config *config)
{
	int i;
	int err;
	pthread_t pid[3];
	R.run = 1;
	R.exit = 0;
	pthread_mutex_init(&R.mutex, NULL); 
	pthread_cond_init(&R.cond, NULL);
	if (config->daemon)
		silly_daemon(config);
	signal_init();
	silly_timer_init();
	err = silly_socket_init();
	if (err < 0) {
		fprintf(stderr, "%s socket init fail:%d\n", config->selfname, err);
		exit(-1);
	}
	silly_worker_init();
	srand(time(NULL));
	thread_create(&pid[0], thread_socket, NULL);
	thread_create(&pid[1], thread_timer, NULL);
	thread_create(&pid[2], thread_worker, config);
	fprintf(stdout, "%s is running ...\n", config->selfname);
	for (i = 0; i < 3; i++)
		pthread_join(pid[i], NULL);
	pthread_mutex_destroy(&R.mutex);
	pthread_cond_destroy(&R.cond);
	silly_worker_exit();
	silly_timer_exit();
	silly_socket_exit();
	fprintf(stdout, "%s has already exit...\n", config->selfname);
	return ;
}

void 
silly_exit()
{
	R.exit = 1;
}

