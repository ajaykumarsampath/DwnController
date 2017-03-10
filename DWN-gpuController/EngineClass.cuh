/*
 * EngineClass.cuh
 *
 *  Created on: Feb 24, 2017
 *      Author: control
 */

#ifndef ENGINECLASS_CUH_
#define ENGINECLASS_CUH_
#include "DefinitionHeader.h"
//TODO Include the exact preconditioning for the constraints
__global__ void preconditionSystem(real_t *matF, real_t *matG, real_t *dualDiagPrcnd, real_t *scaleVec,
		uint_t nx, uint_t nu){
	//int tid = blockIdx.x * blockDim.x + threadIdx.x;
	int currentThread = threadIdx.x;
	int currentBlock  = blockIdx.x;
	int matFDim = 2*nx*nx;
	int matGDim = nu*nu;
	real_t probValue = scaleVec[ currentBlock ];
	real_t currentScaleValue = dualDiagPrcnd[ currentThread ];
	/*if( currentThread < nx){
		uint_t matFIdx = currentBlock * matFDim + (nx*currentThread + currentThread);
		matF[ matFIdx ] = scaleValue * probValue;
	}else if( currentThread > nx & currentThread < 2*nx){
		uint_t matFIdx = currentBlock * matFDim + (nx*currentThread + currentThread - nx);
		matF[ matFIdx] = scaleValue * probValue;
	}else{
		uint_t rowIdx = currentThread -2*nx;
		uint_t matGIdx = currentBlock * matGDim + (nu*rowIdx + rowIdx );
		matG[ matGIdx ] = scaleValue * probValue;
	}*/
	if( currentThread < nu ){
		int matGIdx = currentBlock*matGDim + nu*currentThread + currentThread;
		matG[ matGIdx ] = probValue * currentScaleValue;
	}else if( currentThread > nx & currentThread < nx + nu){
		int rowIdx = currentThread - nu;
		int matFIdx = currentBlock*matFDim + 2*nx*rowIdx + rowIdx;
		matF[matFIdx] = probValue * currentScaleValue;
	}else{
		int rowIdx = currentThread - nu;
		//int matFIdx = currentBlock*matFDim + nx*rowIdx + rowIdx - nx;
		int matFIdx = currentBlock*matFDim + 2*nx*(rowIdx - nx) + rowIdx;
		matF[matFIdx] = probValue * currentScaleValue;
	}
}

__global__ void testGPUAdd(real_t *matF, real_t *matG, uint_t k){
	int tid = blockIdx.x * blockDim.x + threadIdx.x;
	matG[tid] = tid;
	matF[tid] = k*matG[tid];
}

class Engine{
public:
	Engine(DWNnetwork *myNetwork, Forecastor *myForecastor, unitTest *ptrMyTestor);
	void allocateForecastDevice();
	void allocateSystemDevice();
	void initialiseForecastDevice();
	void initialiseSystemDevice();
	void factorStep();
	//void invertMat(real_t** src, real_t** dst, uint_t n, uint_t batchSize);
	void inverseBatchMat(float** src, float** dst, int n, int batchSize);
	void testInverse();
	void testPrecondtioningFunciton();
	void deallocateForecastDevice();
	void deallocateSystemDevice();
	void testStupidFunction();
	friend class SMPCController;
	~Engine();
private:
	DWNnetwork	*ptrMyNetwork;
	Forecastor  *ptrMyForecastor;
	unitTest *ptrMyTestor;
	// network
	real_t *devSysMatB, *devSysMatF, *devSysMatG, *devSysMatL, *devSysMatLhat;
	real_t **devPtrSysMatB, **devPtrSysMatF, **devPtrSysMatG, **devPtrSysMatL, **devPtrSysMatLhat;
	// network constraints
	real_t *devSysXmin, *devSysXmax, *devSysXs, *devSysUmin, *devSysUmax;
	// cost function
	real_t *devSysCostW, *devSysCostAlpha1, *devSysCostAlpha2;
	real_t **devPtrSysCostW;
	// forecaster memory
	uint_t *devTreeStages, *devTreeNodesPerStage, *devTreeNodesPerStageCumul, *devTreeLeaves,
	*devTreeNumChildren, *devTreeAncestor, *devTreeNumChildrenCumul;
	real_t *devTreeProb,*devTreeValue, *devForecastValue;
	// factor matrices
	real_t *devMatPhi, *devMatPsi, *devMatTheta, *devMatOmega, *devMatSigma, *devMatD,
	*devMatF, *devMatG;
	real_t **devPtrMatPhi, **devPtrMatPsi, **devPtrMatTheta, **devPtrMatOmega,
	**devPtrMatSigma, **devPtrMatD, **devPtrMatF, **devPtrMatG;
	real_t *devVecUhat, *devVecBeta, *devVecE;
	cublasHandle_t handle;
};

Engine::Engine(DWNnetwork *myNetwork, Forecastor *myForecastor, unitTest *myTestor){
	cout << "allocating memory for the engine \n";
	ptrMyNetwork = myNetwork;
	ptrMyForecastor = myForecastor;
	ptrMyTestor = myTestor;
	uint_t nx = ptrMyNetwork->NX;
	uint_t nu = ptrMyNetwork->NU;
	uint_t nv = ptrMyNetwork->NV;
	uint_t nodes = ptrMyForecastor->N_NODES;

	allocateSystemDevice();
	allocateForecastDevice();
	cublasCreate(&handle);
	_CUDA( cudaMalloc((void**)&devMatPhi, 2*nodes*nv*nx*sizeof(real_t)) );
	_CUDA( cudaMalloc((void**)&devMatPsi, nodes*nu*nv*sizeof(real_t)) );
	_CUDA( cudaMalloc((void**)&devMatTheta, nodes*nx*nv*sizeof(real_t)) );
	_CUDA( cudaMalloc((void**)&devMatOmega, nodes*nv*nv*sizeof(real_t)) );
	_CUDA( cudaMalloc((void**)&devMatSigma, nodes*nv*sizeof(real_t)) );
	_CUDA( cudaMalloc((void**)&devMatD, 2*nodes*nv*nx*sizeof(real_t)) );
	_CUDA( cudaMalloc((void**)&devMatF, nodes*nv*nu*sizeof(real_t)) );
	_CUDA( cudaMalloc((void**)&devMatG, nodes*nv*nx*sizeof(real_t)) );
	_CUDA( cudaMalloc((void**)&devVecUhat, nodes*nu*sizeof(real_t)) );
	_CUDA( cudaMalloc((void**)&devVecBeta, nodes*nv*sizeof(real_t)) );
	_CUDA( cudaMalloc((void**)&devVecE, nodes*nx*sizeof(real_t)) );

	_CUDA( cudaMalloc((void**)&devPtrMatPhi, nodes*sizeof(real_t*)) );
	_CUDA( cudaMalloc((void**)&devPtrMatPsi, nodes*sizeof(real_t*)) );
	_CUDA( cudaMalloc((void**)&devPtrMatTheta, nodes*sizeof(real_t*)) );
	_CUDA( cudaMalloc((void**)&devPtrMatOmega, nodes*sizeof(real_t*)) );
	_CUDA( cudaMalloc((void**)&devPtrMatSigma, nodes*sizeof(real_t*)) );
	_CUDA( cudaMalloc((void**)&devPtrMatD, nodes*sizeof(real_t*)) );
	_CUDA( cudaMalloc((void**)&devPtrMatF, nodes*sizeof(real_t*)) );
	_CUDA( cudaMalloc((void**)&devPtrMatG, nodes*sizeof(real_t*)) );

	real_t** ptrMatPhi = new real_t*[nodes];
	real_t** ptrMatPsi = new real_t*[nodes];
	real_t** ptrMatTheta = new real_t*[nodes];
	real_t** ptrMatSigma = new real_t*[nodes];
	real_t** ptrMatOmega = new real_t*[nodes];
	real_t** ptrMatD = new real_t*[nodes];
	real_t** ptrMatF = new real_t*[nodes];
	real_t** ptrMatG = new real_t*[nodes];

	for(int i = 0;i < nodes; i++){
		ptrMatPhi[i] = &devMatPhi[2*i*nv*nx];
		ptrMatPsi[i] = &devMatPsi[i*nv*nu];
		ptrMatTheta[i] = &devMatTheta[i*nx*nv];
		ptrMatOmega[i] = &devMatOmega[i*nv*nv];
		ptrMatSigma[i] = &devMatSigma[i*nv];
		ptrMatD[i] = &devMatD[2*i*nv*nx];
		ptrMatF[i] = &devMatF[i*nv*nu];
		ptrMatG[i] = &devMatG[i*nv*nx];
	}

	_CUDA( cudaMemcpy(devPtrMatPhi, ptrMatPhi, nodes*sizeof(real_t*), cudaMemcpyHostToDevice) );
	_CUDA( cudaMemcpy(devPtrMatPsi, ptrMatPsi, nodes*sizeof(real_t*), cudaMemcpyHostToDevice) );
	_CUDA( cudaMemcpy(devPtrMatTheta, ptrMatTheta, nodes*sizeof(real_t*), cudaMemcpyHostToDevice) );
	_CUDA( cudaMemcpy(devPtrMatSigma, ptrMatSigma, nodes*sizeof(real_t*), cudaMemcpyHostToDevice) );
	_CUDA( cudaMemcpy(devPtrMatOmega, ptrMatOmega, nodes*sizeof(real_t*), cudaMemcpyHostToDevice) );
	_CUDA( cudaMemcpy(devPtrMatD, ptrMatD, nodes*sizeof(real_t*), cudaMemcpyHostToDevice) );
	_CUDA( cudaMemcpy(devPtrMatF, ptrMatF, nodes*sizeof(real_t*), cudaMemcpyHostToDevice) );
	_CUDA( cudaMemcpy(devPtrMatG, ptrMatG, nodes*sizeof(real_t*), cudaMemcpyHostToDevice) );

	delete [] ptrMatPhi;
	delete [] ptrMatPsi;
	delete [] ptrMatTheta;
	delete [] ptrMatSigma;
	delete [] ptrMatOmega;
	delete [] ptrMatD;
	delete [] ptrMatF;
	delete [] ptrMatG;
}

void Engine::allocateForecastDevice(){
	uint_t nodes = ptrMyForecastor->N_NODES;
	uint_t N = ptrMyForecastor->N;
	uint_t K = ptrMyForecastor->K;
	uint_t ND = ptrMyNetwork->ND;
	uint_t N_NONLEAF_NODES = ptrMyForecastor->N_NONLEAF_NODES;
	_CUDA( cudaMalloc((void**)&devTreeStages, nodes*sizeof(uint_t)) );
	_CUDA( cudaMalloc((void**)&devTreeNodesPerStage, (N + 1)*sizeof(uint_t)) );
	_CUDA( cudaMalloc((void**)&devTreeNodesPerStageCumul, (N + 2)*sizeof(uint_t)) );
	_CUDA( cudaMalloc((void**)&devTreeLeaves, K*sizeof(uint_t)) );
	_CUDA( cudaMalloc((void**)&devTreeNumChildren, N_NONLEAF_NODES*sizeof(uint_t)) );
	_CUDA( cudaMalloc((void**)&devTreeAncestor, nodes*sizeof(uint_t)) );
	_CUDA( cudaMalloc((void**)&devTreeNumChildrenCumul, nodes*sizeof(uint_t)) );
	_CUDA( cudaMalloc((void**)&devTreeProb, nodes*sizeof(real_t)) );
	_CUDA( cudaMalloc((void**)&devTreeValue, nodes*ND*sizeof(real_t)) );
	_CUDA( cudaMalloc((void**)&devForecastValue, N*ND*sizeof(real_t)) );
}

void Engine::initialiseForecastDevice(){
	uint_t nodes = ptrMyForecastor->N_NODES;
	uint_t N = ptrMyForecastor->N;
	uint_t K = ptrMyForecastor->K;
	uint_t ND = ptrMyNetwork->ND;
	uint_t N_NONLEAF_NODES = ptrMyForecastor->N_NONLEAF_NODES;
	_CUDA( cudaMemcpy(devTreeStages, ptrMyForecastor->stages, nodes*sizeof(uint_t), cudaMemcpyHostToDevice) );
	_CUDA( cudaMemcpy(devTreeNodesPerStage, ptrMyForecastor->nodesPerStage, (N + 1)*sizeof(uint_t), cudaMemcpyHostToDevice) );
	_CUDA( cudaMemcpy(devTreeNodesPerStageCumul, ptrMyForecastor->nodesPerStageCumul, (N + 2)*sizeof(uint_t), cudaMemcpyHostToDevice) );
	_CUDA( cudaMemcpy(devTreeLeaves, ptrMyForecastor->leaves, K*sizeof(uint_t), cudaMemcpyHostToDevice) );
	_CUDA( cudaMemcpy(devTreeNumChildren, ptrMyForecastor->nChildren, N_NONLEAF_NODES*sizeof(uint_t), cudaMemcpyHostToDevice) );
	_CUDA( cudaMemcpy(devTreeAncestor, ptrMyForecastor->ancestor, nodes*sizeof(uint_t), cudaMemcpyHostToDevice) );
	_CUDA( cudaMemcpy(devTreeNumChildrenCumul, ptrMyForecastor->nChildrenCumul, nodes*sizeof(uint_t), cudaMemcpyHostToDevice) );
	_CUDA( cudaMemcpy(devTreeProb, ptrMyForecastor->probNode, nodes*sizeof(real_t), cudaMemcpyHostToDevice) );
	_CUDA( cudaMemcpy(devTreeValue, ptrMyForecastor->valueNode, nodes*ND*sizeof(real_t), cudaMemcpyHostToDevice) );
	_CUDA( cudaMemcpy(devForecastValue, ptrMyForecastor->dHat, N*ND*sizeof(real_t), cudaMemcpyHostToDevice) );
}

void Engine::allocateSystemDevice(){
	uint_t nx = ptrMyNetwork->NX;
	uint_t nu = ptrMyNetwork->NU;
	uint_t nv = ptrMyNetwork->NV;
	uint_t ne = ptrMyNetwork->NE;
	uint_t nd = ptrMyNetwork->ND;
	uint_t nodes = ptrMyForecastor->N_NODES;
	uint_t ns = ptrMyForecastor->K;
	_CUDA( cudaMalloc((void**)&devSysMatB, ns*nx*nu*sizeof(real_t)) );
	_CUDA( cudaMalloc((void**)&devSysMatL, ns*nv*nu*sizeof(real_t)) );
	_CUDA( cudaMalloc((void**)&devSysMatLhat, ns*nu*nd*sizeof(real_t)) );
	_CUDA( cudaMalloc((void**)&devSysMatF, 2*nodes*nx*nx*sizeof(real_t)) );
	_CUDA( cudaMalloc((void**)&devSysMatG, nodes*nu*nu*sizeof(real_t)) );
	_CUDA( cudaMalloc((void**)&devSysXmin, nodes*nx*sizeof(real_t)) );
	_CUDA( cudaMalloc((void**)&devSysXmax, nodes*nx*sizeof(real_t)) );
	_CUDA( cudaMalloc((void**)&devSysXs, nodes*nx*sizeof(real_t)) );
	_CUDA( cudaMalloc((void**)&devSysUmin, nodes*nu*sizeof(real_t)) );
	_CUDA( cudaMalloc((void**)&devSysUmax, nodes*nu*sizeof(real_t)) );
	_CUDA( cudaMalloc((void**)&devSysCostW, nodes*nv*nv*sizeof(real_t)) );

	_CUDA( cudaMalloc((void**)&devPtrSysMatB, nodes*sizeof(real_t*)) );
	_CUDA( cudaMalloc((void**)&devPtrSysMatL, nodes*sizeof(real_t*)) );
	_CUDA( cudaMalloc((void**)&devPtrSysMatLhat, nodes*sizeof(real_t*)) );
	_CUDA( cudaMalloc((void**)&devPtrSysMatF, nodes*sizeof(real_t*)) );
	_CUDA( cudaMalloc((void**)&devPtrSysMatG, nodes*sizeof(real_t*)) );
	_CUDA( cudaMalloc((void**)&devPtrSysCostW, nodes*sizeof(real_t*)) );

	real_t **ptrSysMatB = new real_t*[nodes];
	real_t **ptrSysMatL = new real_t*[nodes];
	real_t **ptrSysMatLhat = new real_t*[nodes];
	real_t **ptrSysMatF = new real_t*[nodes];
	real_t **ptrSysMatG = new real_t*[nodes];
	real_t **ptrSysCostW = new real_t*[nodes];

	for(int i = 0; i < nodes; i++ ){
		ptrSysMatF[i] = &devSysMatF[i*2*nx*nx];
		ptrSysMatG[i] = &devSysMatG[i*nu*nu];
		ptrSysCostW[i] = &devSysCostW[i*nv*nv];
	}
	for(int k = 0; k < ptrMyForecastor->N; k++){
		for(int j = 0; j < ptrMyForecastor->nodesPerStage[k]; j++){
			ptrSysMatB[ptrMyForecastor->nodesPerStageCumul[k] + j] = &devSysMatB[j*nx*nu];
			ptrSysMatL[ptrMyForecastor->nodesPerStageCumul[k] + j] = &devSysMatL[j*nu*nv];
			ptrSysMatLhat[ptrMyForecastor->nodesPerStageCumul[k] + j] = &devSysMatLhat[j*nu*nd];
		}
	}

	_CUDA( cudaMemcpy(devPtrSysMatB, ptrSysMatB, nodes*sizeof(real_t*), cudaMemcpyHostToDevice) );
	_CUDA( cudaMemcpy(devPtrSysMatL, ptrSysMatL, nodes*sizeof(real_t*), cudaMemcpyHostToDevice) );
	_CUDA( cudaMemcpy(devPtrSysMatLhat, ptrSysMatLhat, nodes*sizeof(real_t*), cudaMemcpyHostToDevice) );
	_CUDA( cudaMemcpy(devPtrSysMatF, ptrSysMatF, nodes*sizeof(real_t*), cudaMemcpyHostToDevice) );
	_CUDA( cudaMemcpy(devPtrSysMatG, ptrSysMatG, nodes*sizeof(real_t*), cudaMemcpyHostToDevice) );
	_CUDA( cudaMemcpy(devPtrSysCostW, ptrSysCostW, nodes*sizeof(real_t*), cudaMemcpyHostToDevice) );

	delete [] ptrSysMatB;
	delete [] ptrSysMatL;
	delete [] ptrSysMatLhat;
	delete [] ptrSysMatF;
	delete [] ptrSysMatG;
	delete [] ptrSysCostW;
}

void Engine::initialiseSystemDevice(){
	uint_t nodes = ptrMyForecastor->N_NODES;
	uint_t nx = ptrMyNetwork->NX;
	uint_t nu = ptrMyNetwork->NU;
	uint_t nv = ptrMyNetwork->NV;
	uint_t ns = ptrMyForecastor->K;
	uint_t nd = ptrMyForecastor->DIM_NODE;
	uint_t N = ptrMyForecastor->N;
	uint_t numBlock, prevNodes;
	uint_t matFIdx, matGIdx;
	real_t *devMatDiagPrcnd;
	real_t *devCostMatW, *devMatvariable;
	real_t alpha = 1, beta = 0;
	//real_t *x = new real_t[2*nodes*nu*nu];
	//real_t **y = new real_t*[nodes];

	_CUDA( cudaMalloc((void**)&devMatDiagPrcnd, N*(2*nx + nu)*sizeof(real_t)) );
	_CUDA( cudaMemcpy(devMatDiagPrcnd, ptrMyNetwork->matDiagPrecnd, N*(2*nx + nu)*sizeof(real_t), cudaMemcpyHostToDevice) );
	for (int iScen = 0; iScen < ns; iScen++){
		_CUDA( cudaMemcpy(&devSysMatB[iScen*nx*nu], ptrMyNetwork->matB, nx*nu*sizeof(real_t), cudaMemcpyHostToDevice) );
		_CUDA( cudaMemcpy(&devSysMatL[iScen*nu*nv], ptrMyNetwork->matL, nu*nv*sizeof(real_t), cudaMemcpyHostToDevice) );
		_CUDA( cudaMemcpy(&devSysMatLhat[iScen*nu*nd], ptrMyNetwork->matLhat, nu*nd*sizeof(real_t), cudaMemcpyHostToDevice) );
	}
	_CUDA( cudaMalloc((void**)&devCostMatW, nu*nu*sizeof(real_t)) );
	_CUDA( cudaMalloc((void**)&devMatvariable, nu*nv*sizeof(real_t)) );
	_CUDA( cudaMemcpy(devCostMatW, ptrMyNetwork->matCostW, nu*nu*sizeof(real_t), cudaMemcpyHostToDevice) );
	_CUBLAS( cublasSgemm_v2(handle, CUBLAS_OP_N, CUBLAS_OP_N, nu, nv, nu, &alpha, (const float*) devCostMatW, nu,
			(const float*) devSysMatL, nu, &beta, devMatvariable, nu) );
	_CUBLAS( cublasSgemm_v2(handle, CUBLAS_OP_T, CUBLAS_OP_N, nv, nv, nu, &alpha, (const float*) devSysMatL, nu,
			(const float*) devMatvariable, nu, &beta, devCostMatW, nv) );
	ptrMyTestor->checkObjectiveMatR<real_t>(devCostMatW);

	_CUDA( cudaMemset(devSysMatF, 0, nodes*2*nx*nx*sizeof(real_t)) );
	_CUDA( cudaMemset(devSysMatG, 0, nodes*nu*nu*sizeof(real_t)) );
	for (int iStage = 0; iStage < N; iStage++){
		numBlock = ptrMyForecastor->nodesPerStage[iStage];
		prevNodes = ptrMyForecastor->nodesPerStageCumul[iStage];
		matFIdx = prevNodes*(2*nx * nx);
		matGIdx = prevNodes*(nu * nu);
		preconditionSystem<<<numBlock, 2*nx+nu>>>(&devSysMatF[matFIdx], &devSysMatG[matGIdx],
				&devMatDiagPrcnd[iStage*(2*nx + nu)], &devTreeProb[prevNodes], nx, nu );
	}
	/*
	_CUDA( cudaMemcpy(y, devPtrSysMatF, nodes*sizeof(real_t*), cudaMemcpyDeviceToHost) );

	for( int iNodes = 0; iNodes < nodes; iNodes++){
		//cout<< y[iNodes] << " ";
		_CUDA( cudaMemcpy(x, &devSysMatF[iNodes*2*nx*nx], 2*nx*nx*sizeof(real_t), cudaMemcpyDeviceToHost));
		for (int iRow = 0; iRow < 2*nx; iRow++){
			for(int iCol = 0; iCol < nx; iCol++){
				cout<< x[2*iCol*nx + iRow] << " ";
				//cout<< 2*iCol*nx + iRow << " ";
			}
			cout << "\n";
		}
	}

	_CUDA( cudaMemcpy(x, devMatDiagPrcnd, N*(2*nx + nu)*sizeof(real_t), cudaMemcpyDeviceToHost));
	for (int i = 0; i < N*(2*nx + nu); i++)
		cout<< x[i] << " " << i << " ";
	cout<<"\n";
	_CUDA( cudaMemcpy(x, devTreeProb, N*sizeof(real_t), cudaMemcpyDeviceToHost) );
	for (int i = 0; i < N; i++ )
		cout<< x[i] << " ";
	cout<<"\n";

	for( int iNodes = 0; iNodes < nodes; iNodes++){
		//cout<< y[iNodes] << " ";
		_CUDA( cudaMemcpy(x, &devSysMatG[iNodes*nu*nu], nu*nu*sizeof(real_t), cudaMemcpyDeviceToHost));
		for (int iRow = 0; iRow < nu; iRow++){
			for(int iCol = 0; iCol < nu; iCol++){
				cout<< x[iCol*nu + iRow] << " ";
			}
			cout << "\n";
		}
	}
	 */
	for (int iNodes = 0; iNodes < nodes; iNodes++){
		_CUDA( cudaMemcpy(&devSysXmin[iNodes*nx], ptrMyNetwork->vecXmin, nx*sizeof(real_t), cudaMemcpyHostToDevice) );
		_CUDA( cudaMemcpy(&devSysXmax[iNodes*nx], ptrMyNetwork->vecXmax, nx*sizeof(real_t), cudaMemcpyHostToDevice) );
		_CUDA( cudaMemcpy(&devSysXs[iNodes*nx], ptrMyNetwork->vecXsafe, nx*sizeof(real_t), cudaMemcpyHostToDevice) );
		_CUDA( cudaMemcpy(&devSysUmin[iNodes*nx], ptrMyNetwork->vecUmin, nu*sizeof(real_t), cudaMemcpyHostToDevice) );
		_CUDA( cudaMemcpy(&devSysUmax[iNodes*nx], ptrMyNetwork->vecUmax, nu*sizeof(real_t), cudaMemcpyHostToDevice) );
		_CUDA( cudaMemcpy(&devSysCostW[iNodes*nv*nv], devCostMatW, nv*nv*sizeof(real_t), cudaMemcpyDeviceToDevice) );
		_CUBLAS( cublasSscal_v2(handle, nx,&ptrMyForecastor->probNode[iNodes], &devSysXmax[iNodes*nx], 1) );
		_CUBLAS( cublasSscal_v2(handle, nx,&ptrMyForecastor->probNode[iNodes], &devSysXmin[iNodes*nx], 1) );
		_CUBLAS( cublasSscal_v2(handle, nx,&ptrMyForecastor->probNode[iNodes], &devSysXs[iNodes*nx], 1) );
		_CUBLAS( cublasSscal_v2(handle, nu,&ptrMyForecastor->probNode[iNodes], &devSysUmax[iNodes*nu], 1) );
		_CUBLAS( cublasSscal_v2(handle, nu,&ptrMyForecastor->probNode[iNodes], &devSysUmin[iNodes*nu], 1) );
		_CUBLAS( cublasSscal_v2(handle, nv*nv, &ptrMyForecastor->probNode[iNodes], &devSysCostW[iNodes*nv*nv], 1) );
	}
	_CUDA( cudaFree(devMatDiagPrcnd) );
	_CUDA( cudaFree(devMatvariable) );
	_CUDA( cudaFree(devCostMatW) );
}

void  Engine::factorStep(){
	real_t scale[2] = {-0.5, 1};
	real_t alpha = 1.0;
	real_t beta = 0.0;
	real_t negAlpha = -1.0;
	uint_t iStageCumulNodes, iStageNodes;
	real_t *devMatBbar, *devMatGbar;
	real_t **devPtrMatBbar, **devPtrMatGbar, **ptrMatBbar, **ptrMatGbar;
	uint_t ns = ptrMyForecastor->K;
	uint_t nx = ptrMyNetwork->NX;
	uint_t nu = ptrMyNetwork->NU;
	uint_t nv = ptrMyNetwork->NV;
	uint_t N = ptrMyForecastor->N;
	//real_t *x = new real_t[2*nodes*nu*nu];
	//real_t **y = new real_t*[nodes];
	_CUDA( cudaMalloc((void**)&devMatBbar, nv*nx*ns*sizeof(real_t)) );
	_CUDA( cudaMalloc((void**)&devMatGbar, nu*nv*ns*sizeof(real_t)) );
	_CUDA( cudaMalloc((void**)&devPtrMatBbar, ns*sizeof(real_t*)) );
	_CUDA( cudaMalloc((void**)&devPtrMatGbar, ns*sizeof(real_t*)) );
	ptrMatBbar = new real_t*[ns];
	ptrMatGbar = new real_t*[ns];
	for(int i = 0; i < ns; i++){
		ptrMatBbar[i] = &devMatBbar[i*nx*nv];
		ptrMatGbar[i] = &devMatGbar[i*nu*nv];
	}
	_CUDA( cudaMemcpy(devPtrMatGbar, ptrMatGbar, ns*sizeof(real_t*), cudaMemcpyHostToDevice) );
	_CUDA( cudaMemcpy(devPtrMatBbar, ptrMatBbar, ns*sizeof(real_t*), cudaMemcpyHostToDevice) );

	// Bbar'
	_CUBLAS( cublasSgemmBatched(handle, CUBLAS_OP_T, CUBLAS_OP_T, nv, nx, nu, &alpha, (const float**)devPtrSysMatL, nu,
			(const float**)devPtrSysMatB, nx, &beta, devPtrMatBbar, nv, ns));

	for(int iStage = N-1; iStage > -1; iStage--){
		iStageCumulNodes = ptrMyForecastor->nodesPerStageCumul[iStage];
		iStageNodes = ptrMyForecastor->nodesPerStage[iStage];
		// omega=(p_k\bar{R})^{-1}
		inverseBatchMat( &devPtrSysCostW[iStageCumulNodes], &devPtrMatOmega[iStageCumulNodes], nv, iStageNodes );

		// effinet_f=GBar
		_CUBLAS(cublasSgemmBatched(handle, CUBLAS_OP_T, CUBLAS_OP_T, nv, nu, nu, &alpha, (const float**)devPtrSysMatL, nu,
				(const float**)&devPtrMatG[iStageCumulNodes], nu, &beta, &devPtrMatF[iStageCumulNodes], nv, iStageNodes) );

		// effinet_g=\bar{B}'
		_CUDA( cudaMemcpy(&devMatG[nx*nv*iStageCumulNodes], devMatBbar, nx*nv*iStageNodes*sizeof(real_t), cudaMemcpyDeviceToDevice));

		// effinet_d=\bar{B}'F'
		_CUBLAS(cublasSgemmBatched(handle, CUBLAS_OP_N, CUBLAS_OP_T, nv, 2*nx, nx, &alpha, (const float**)devPtrMatBbar, nv,
				(const float**)&devPtrSysMatF[iStageCumulNodes], 2*nx, &beta, &devPtrMatD[iStageCumulNodes], nv, iStageNodes));


		// phi=\omega \bar{B}'F'
		_CUBLAS(cublasSgemmBatched(handle, CUBLAS_OP_N, CUBLAS_OP_N, nv, 2*nx, nv, &scale[0], (const float**)
				&devPtrMatOmega[iStageCumulNodes], nv, (const float**)&devPtrMatD[iStageCumulNodes], nv, &beta,
				&devPtrMatPhi[iStageCumulNodes], nv, iStageNodes));

		// theta=\omega \bar{B}'
		_CUBLAS(cublasSgemmBatched(handle, CUBLAS_OP_N, CUBLAS_OP_N, nv, nx, nv, &scale[0], (const float**)
				&devPtrMatOmega[iStageCumulNodes], nv, (const float**)devPtrMatBbar, nv, &beta,
				&devPtrMatTheta[iStageCumulNodes], nv , iStageNodes));

		// psi=\omega \bar{G}'
		_CUBLAS(cublasSgemmBatched(handle, CUBLAS_OP_N, CUBLAS_OP_N, nv, nu, nv, &scale[0],(const float**)
				&devPtrMatOmega[iStageCumulNodes], nv, (const float**)&devPtrMatF[iStageCumulNodes], nv, &beta,
				&devPtrMatPsi[iStageCumulNodes], nv, iStageNodes));
		/**/
	}

	printf("Effinet factor step is completed\n");
	delete [] ptrMatBbar;
	delete [] ptrMatGbar;

	_CUDA(cudaFree(devMatBbar));
	_CUDA(cudaFree(devMatGbar));
	_CUDA(cudaFree(devPtrMatBbar));
	_CUDA(cudaFree(devPtrMatGbar));

}

void Engine::testStupidFunction(){
	real_t *a, *b;
	a = new real_t [ptrMyForecastor->N_NODES];
	b = new real_t [ptrMyForecastor->N_NODES];
	testGPUAdd<<<2, 2>>>(devMatF , devMatG, 2);
	/*
	for (int i = 0; i<ptrMyForecastor->N_NODES; i++)
		a[i] = (real_t) 2 * i;
	_CUDA(cudaMemcpy(devMatPhi,a, ptrMyForecastor->N_NODES*sizeof(real_t), cudaMemcpyHostToDevice));
	_CUDA(cudaMemcpy(b, devMatPhi, ptrMyForecastor->N_NODES*sizeof(real_t), cudaMemcpyDeviceToHost));
	 */
	_CUDA( cudaMemcpy(a, devMatF, 4*sizeof(real_t), cudaMemcpyDeviceToHost) );
	_CUDA( cudaMemcpy(b, devMatG, 4*sizeof(real_t), cudaMemcpyDeviceToHost) );
	for (int i = 0; i < 4; i++)
		cout <<  a[i] << " " << b[i] << " ";
	delete [] a;
	delete [] b;
}

void Engine::inverseBatchMat(float** src, float** dst, int n, int batchSize){
	uint_t *P, *INFO;

	_CUDA(cudaMalloc((void**)&P, n * batchSize * sizeof(uint_t)));
	_CUDA(cudaMalloc((void**)&INFO, batchSize * sizeof(uint_t)));

	uint_t lda = n;

	real_t** x=(real_t**)malloc(batchSize*sizeof(real_t*));
	real_t* y=(real_t*)malloc(n*n*sizeof(real_t));


	_CUBLAS(cublasSgetrfBatched(handle,n,src,lda,P,INFO,batchSize));

	uint_t INFOh[batchSize];

	_CUDA(cudaMemcpy(INFOh,INFO,batchSize*sizeof(uint_t),cudaMemcpyDeviceToHost));
	for (uint_t i = 0; i < batchSize; i++){
		if(INFOh[i] != 0)
		{
			fprintf(stderr, "Factorization of matrix %d Failed: Matrix may be singular\n", i);
			cudaDeviceReset();
			exit(EXIT_FAILURE);
		}
	}

	_CUBLAS(cublasSgetriBatched(handle,n,(const float **)src,lda,P,dst,lda,INFO,batchSize));
	_CUDA(cudaMemcpy(INFOh,INFO,batchSize*sizeof(uint_t),cudaMemcpyDeviceToHost));

	for (uint_t i = 0; i < batchSize; i++)
		if(INFOh[i] != 0)
		{
			fprintf(stderr, "Inversion of matrix %d Failed: Matrix may be singular\n", i);
			cudaDeviceReset();
			exit(EXIT_FAILURE);
		}

	_CUDA(cudaFree(P));
	_CUDA(cudaFree(INFO));
}

void Engine::testInverse(){
	uint_t size_n= 3;
	uint_t batch_size=2;

	real_t* matA=(real_t*)malloc(size_n*size_n*batch_size*sizeof(real_t));
	real_t* inv_matA=(real_t*)malloc(size_n*size_n*batch_size*sizeof(real_t));
	real_t** ptr_matA=(real_t**)malloc(batch_size*sizeof(real_t*));
	real_t** ptr_inv_matA=(real_t**)malloc(batch_size*sizeof(real_t*));

	real_t *dev_matA,*dev_inv_matA,**dev_ptr_matA,**dev_ptr_inv_matA;

	_CUDA(cudaMalloc((void**)&dev_matA,batch_size*size_n*size_n*sizeof(real_t)));
	_CUDA(cudaMalloc((void**)&dev_inv_matA,batch_size*size_n*size_n*sizeof(real_t)));

	_CUDA(cudaMalloc((void**)&dev_ptr_matA,batch_size*sizeof(real_t*)));
	_CUDA(cudaMalloc((void**)&dev_ptr_inv_matA,batch_size*sizeof(real_t*)));

	real_t temp;
	for(int k=0;k<batch_size;k++){
		for(int i=0;i<size_n;i++)
			for(int j=0;j<size_n;j++){
				temp=(real_t)(rand() % 29)/32;
				matA[k*size_n*size_n+i*size_n+j]=temp;
				if(i==j){
					matA[k*size_n*size_n+i*size_n+j]=0.5;
				}
			}
		ptr_matA[k]=&dev_matA[k*size_n*size_n];
		ptr_inv_matA[k]=&dev_inv_matA[k*size_n*size_n];
	}
	for(int k=0;k<batch_size;k++){
		printf("matrix :%d \n",k);
		for(int i=0;i<size_n;i++){
			for(int j=0;j<size_n;j++){
				printf("%f ",matA[k*size_n*size_n+i*size_n+j]);
			}
			printf("\n");
		}
	}

	_CUDA(cudaMemcpy(dev_matA,matA,batch_size*size_n*size_n*sizeof(real_t),cudaMemcpyHostToDevice));
	_CUDA(cudaMemcpy(dev_ptr_matA,ptr_matA,batch_size*sizeof(real_t*),cudaMemcpyHostToDevice));

	_CUDA(cudaMemcpy(dev_ptr_inv_matA,ptr_inv_matA,batch_size*sizeof(real_t*),cudaMemcpyHostToDevice));


	this->inverseBatchMat(dev_ptr_matA,dev_ptr_inv_matA,size_n,batch_size);
	_CUDA(cudaMemcpy(inv_matA,dev_inv_matA,batch_size*size_n*size_n*sizeof(real_t),cudaMemcpyDeviceToHost));
	for(int k=0;k<batch_size;k++){
		printf("inverse of matrix :%d \n",k);
		for(int i=0;i<size_n;i++){
			for(int j=0;j<size_n;j++){
				printf("%f ",inv_matA[k*size_n*size_n+i*size_n+j]);
			}
			printf("\n");
		}
	}
	printf("Test successful\n");

	free(matA);
	free(ptr_matA);
	free(inv_matA);
	free(ptr_inv_matA);

	_CUDA(cudaFree(dev_matA));
	_CUDA(cudaFree(dev_inv_matA));
	_CUDA(cudaFree(dev_ptr_matA));
	_CUDA(cudaFree(dev_ptr_inv_matA));
}

void Engine::testPrecondtioningFunciton(){
	uint_t nx = ptrMyNetwork->NX;
	uint_t nu = ptrMyNetwork->NU;
	real_t *x = new real_t[2*nu*nu];
	real_t *devMatDiagPrcnd;
	_CUDA( cudaMalloc((void**)&devMatDiagPrcnd, ptrMyForecastor->N*(2*nx + nu)*sizeof(real_t)) );
	_CUDA( cudaMemcpy(devMatDiagPrcnd, ptrMyNetwork->matDiagPrecnd, ptrMyForecastor->N*(2*nx + nu)*sizeof(real_t), cudaMemcpyHostToDevice) );

	preconditionSystem<<<2, 2*nx+nu>>>(&devSysMatF[0], &devSysMatG[0], &devMatDiagPrcnd[0], &devTreeProb[0], nx, nu );
	for (int i = 0; i < 2 ; i++ ){
		_CUDA( cudaMemcpy(x, &devSysMatG[i*nu*nu], nu*nu*sizeof(real_t), cudaMemcpyDeviceToHost));
		for (int iRow = 0; iRow < nu; iRow++){
			for(int iCol = 0; iCol < nu; iCol++){
				cout<< x[iCol*nu + iRow] << " ";
				//cout<< iCol*nu + iRow << " ";
			}
			cout << "\n";
		}
		_CUDA( cudaMemcpy(x, &devSysMatF[i*2*nx*nx], 2*nx*nx*sizeof(real_t), cudaMemcpyDeviceToHost));
		for (int iRow = 0; iRow < 2*nx; iRow++){
			for(int iCol = 0; iCol < nx; iCol++){
				cout<< x[2*iCol*nx + iRow] << " ";
				//cout<< 2*iCol*nx + iRow << " ";
			}
			cout << "\n";
		}
	}
	_CUDA( cudaFree(devMatDiagPrcnd) );
	delete [] x;
}

void Engine::deallocateSystemDevice(){
	_CUDA( cudaFree(devSysMatB) );
	_CUDA( cudaFree(devSysMatL) );
	_CUDA( cudaFree(devSysMatLhat) );
	_CUDA( cudaFree(devSysMatF) );
	_CUDA( cudaFree(devSysMatG) );
	_CUDA( cudaFree(devSysXmin) );
	_CUDA( cudaFree(devSysXmax) );
	_CUDA( cudaFree(devSysXs) );
	_CUDA( cudaFree(devSysUmin) );
	_CUDA( cudaFree(devSysUmax) );

	_CUDA( cudaFree(devPtrSysMatB) );
	_CUDA( cudaFree(devPtrSysMatL) );
	_CUDA( cudaFree(devPtrSysMatLhat) );
	_CUDA( cudaFree(devPtrSysMatF) );
	_CUDA( cudaFree(devPtrSysMatG) );
}

void Engine::deallocateForecastDevice(){
	_CUDA( cudaFree(devTreeStages) );
	_CUDA( cudaFree(devTreeNodesPerStage));
	_CUDA( cudaFree(devTreeLeaves) );
	_CUDA( cudaFree(devTreeNodesPerStageCumul) );
	_CUDA( cudaFree(devTreeNumChildren) );
	_CUDA( cudaFree(devTreeNumChildrenCumul) );
	_CUDA( cudaFree(devTreeValue) );
	_CUDA( cudaFree(devForecastValue) );
}
Engine::~Engine(){
	cout << "removing the memory of the engine \n";
	deallocateSystemDevice();
	deallocateForecastDevice();
	//delete ptrMyForecastor;
	//delete ptrMyNetwork;
	_CUDA(cudaFree(devMatPhi));
	_CUDA(cudaFree(devMatPsi));
	_CUDA(cudaFree(devMatTheta));
	_CUDA(cudaFree(devMatOmega));
	_CUDA(cudaFree(devMatSigma));
	_CUDA(cudaFree(devMatD));
	_CUDA(cudaFree(devMatF));
	_CUDA(cudaFree(devMatG));

	_CUDA(cudaFree(devPtrMatPhi));
	_CUDA(cudaFree(devPtrMatPsi));
	_CUDA(cudaFree(devPtrMatTheta));
	_CUDA(cudaFree(devPtrMatOmega));
	_CUDA(cudaFree(devPtrMatSigma));
	_CUDA(cudaFree(devPtrMatD));
	_CUDA(cudaFree(devPtrMatF));
	_CUDA(cudaFree(devPtrMatG));
	//_CUBLAS(cublasDestroy(handle));
	cublasDestroy_v2(handle);
}


#endif /* ENGINECLASS_CUH_ */